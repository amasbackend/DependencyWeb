module Llm
  # §32-37: turns this PR's already-computed evidence into an operator-facing
  # test scope report. Which code is affected — and now which *screens* — is
  # decided deterministically before the LLM is involved (ScreenCatalog +
  # ScreenImpactLocator via TestScopeInputBuilder); the LLM only translates
  # each batch's changes into steps on those screens, citing real refs.
  #
  # One request per batch instead of one for the whole PR, so a large PR
  # never has to be cut down to fit (the old 30-item cap). A batch whose
  # answer fails validation is asked once more with the exact problems
  # listed; one that still fails, or errors, is reported as such in the
  # report rather than failing the whole analysis. Afterwards every ref is
  # checked: anything neither covered by a case nor explicitly explained
  # becomes a "需要人工確認" item, so no change is silently dropped.
  class AnalyzeTestScope < Actor
    include RepositoryPaths

    input :pull_request_analysis
    # Tests inject an in-memory snapshot; real runs read the bare repo at the
    # PR head (already cloned/fetched earlier in PullRequestAnalysisJob).
    input :snapshot, default: nil, allow_nil: true
    output :test_report

    CONCURRENCY = 4
    MAX_ATTEMPTS_PER_BATCH = 2

    ChunkResult = Struct.new(:chunk, :data, :responses, :duration_ms, :error, :repaired, :supplemented, keyword_init: true)

    def call
      pull_request_analysis.update!(status: "llm_analyzing")

      @started_at = monotonic_now
      @usage = []
      @usage_lock = Mutex.new
      built = TestScopeInputBuilder.call(pull_request_analysis, snapshot: snapshot || head_snapshot)
      results = run_chunks(built.chunks)
      if results.any? && results.all?(&:error)
        raise Provider::Error, "所有批次皆產生失敗：#{results.map(&:error).uniq.first(3).join('；')}"
      end

      _summary_response, summary = run_summary(built, results)
      data = assemble(built, results, summary)
      errors = TestScopeSchema.validate(data)
      raise TestScopeSchema::ValidationError, errors.join("; ") if errors.any?

      self.test_report = persist(data, built)
    rescue StandardError => e
      message = I18n.t("actor.llm.analyze_test_scope.failed", message: e.message)
      record_failed_run(message)
      fail_with(message)
    end

    private

    def project
      pull_request_analysis.project
    end

    def head_snapshot
      RepositorySnapshot.new(git_dir: bare_repo_path, sha: pull_request_analysis.head_sha)
    end

    # --- batches --------------------------------------------------------------

    # A few batches in flight at once; workers only call the provider (no DB
    # access), so they need no connection-pool handling.
    def run_chunks(chunks)
      queue = Queue.new
      chunks.each_with_index { |chunk, i| queue << [ chunk, i ] }
      results = Array.new(chunks.size)

      Array.new([ CONCURRENCY, chunks.size ].min) do
        Thread.new do
          loop do
            chunk, index = queue.pop(true)
            results[index] = run_chunk(chunk)
          rescue ThreadError
            break
          end
        end
      end.each(&:join)

      results
    end

    def run_chunk(chunk)
      started_at = monotonic_now
      responses = []
      prompt = TestScopePrompt.build(chunk.input)
      user_prompt = prompt[:user]
      errors = []

      MAX_ATTEMPTS_PER_BATCH.times do |attempt|
        response = Provider.current.generate(system: prompt[:system], prompt: user_prompt, json: true, temperature: LlmConfig.temperature)
        responses << response
        track_usage(response)
        data, errors = parse_chunk(response, chunk)
        if errors.empty? || attempt == MAX_ATTEMPTS_PER_BATCH - 1
          data = sanitize_chunk(data, chunk) if errors.any?
          data, supplemented = supplement_missing(chunk, prompt, data, responses)
          return ChunkResult.new(chunk: chunk, data: data, responses: responses, duration_ms: elapsed_ms(started_at),
                                 repaired: attempt.positive?, supplemented: supplemented)
        end

        user_prompt = prompt[:user] + TestScopePrompt.repair_note(errors.first(15))
      end
    rescue StandardError => e
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] batch #{chunk.key} failed: #{e.message}")
      ChunkResult.new(chunk: chunk, responses: responses, duration_ms: elapsed_ms(started_at), error: e.message)
    end

    def parse_chunk(response, chunk)
      data = response.parsed_json
      [ data, TestScopeSchema.validate_chunk(data, screen_keys: chunk.screen_keys, refs: chunk.refs) ]
    rescue JSON::ParserError
      [ nil, [ "response is not valid JSON" ] ]
    end

    # A large batch can come back valid but silent on some refs. Ask once,
    # for just those; whatever is still missing afterwards is listed by the
    # report-level coverage check. Returns [data, number of refs asked about].
    def supplement_missing(chunk, prompt, data, responses)
      missing = chunk.refs - accounted_refs(data)
      return [ data, nil ] if missing.empty?

      note = TestScopePrompt.supplement_note(Array(data["test_cases"]).map { |c| c["name"] }, missing)
      response = Provider.current.generate(system: prompt[:system], prompt: prompt[:user] + note, json: true, temperature: LlmConfig.temperature)
      responses << response
      track_usage(response)
      extra = sanitize_chunk(response.parsed_json, chunk)
      merged = data.merge(
        "test_cases" => Array(data["test_cases"]) + extra["test_cases"],
        "uncertain_items" => Array(data["uncertain_items"]) + extra["uncertain_items"],
      )
      [ merged, missing.size ]
    rescue StandardError => e
      Rails.logger.warn("[PRAnalysis:#{pull_request_analysis.id}] supplement for batch #{chunk.key} failed: #{e.message}")
      [ data, missing.size ]
    end

    def accounted_refs(data)
      Array(data["test_cases"]).flat_map { |c| Array(c["impact_item_refs"]) } +
        Array(data["uncertain_items"]).flat_map { |i| Array(i.is_a?(Hash) ? i["refs"] : nil) }
    end

    # Last-resort cleanup after the repair attempt: drop citations of refs
    # the batch doesn't own, and drop cases that still can't be placed on a
    # real screen or have no usable steps — keep everything else.
    def sanitize_chunk(data, chunk)
      return { "test_cases" => [], "uncertain_items" => [] } unless data.is_a?(Hash)

      cases = Array(data["test_cases"]).filter_map do |c|
        next unless c.is_a?(Hash) && chunk.screen_keys.include?(c["screen_key"])

        refs = Array(c["impact_item_refs"]) & chunk.refs
        next if refs.empty? || !Array(c["steps"]).any? || c["name"].blank? || c["expected_result"].blank?

        c.merge(
          "impact_item_refs" => refs,
          "case_type" => TestScopeSchema::CHUNK_CASE_TYPES.include?(c["case_type"]) ? c["case_type"] : "direct_impact",
          "verification_purpose" => c["verification_purpose"].presence || c["name"],
        )
      end
      data.merge("test_cases" => cases, "uncertain_items" => Array(data["uncertain_items"]).select { |i| i.is_a?(Hash) })
    end

    # --- overview -------------------------------------------------------------

    def run_summary(built, results)
      prompt = TestScopePrompt.build_summary(summary_input(built, results))
      response = Provider.current.generate(system: prompt[:system], prompt: prompt[:user], json: true, temperature: LlmConfig.temperature)
      track_usage(response)
      data = response.parsed_json
      [ response, data.is_a?(Hash) ? data : {} ]
    rescue StandardError => e
      # The overview is a convenience over the batches' own results — fall
      # back to a plain one rather than losing every generated case.
      Rails.logger.warn("[PRAnalysis:#{pull_request_analysis.id}] summary call failed: #{e.message}")
      [ nil, {} ]
    end

    def summary_input(built, results)
      {
        pull_request: { number: pull_request_analysis.pr_number, title: pull_request_analysis.pr_title,
                        description: pull_request_analysis.pr_description.to_s.truncate(2_000) },
        batches: results.reject(&:error).map do |r|
          { screens: r.chunk.title, summary: r.data["chunk_summary"], test_cases: Array(r.data["test_cases"]).map { |c| c["name"] } }
        end,
        other_changes: built.mappings.reject { |m| m.bucket.nil? }.group_by(&:bucket)
                                .map { |bucket, ms| { category: ScreenImpactLocator::BUCKET_LABELS[bucket], count: ms.size } },
      }
    end

    # --- merge ----------------------------------------------------------------

    def assemble(built, results, summary)
      cases = results.reject(&:error).flat_map do |r|
        Array(r.data["test_cases"]).map { |c| normalize_case(c, built.catalog) }
      end.uniq { |c| [ c["screen_key"], c["name"] ] }

      uncertain = batch_uncertain_items(results, cases) +
                  built.deterministic_items + failed_batch_items(results) + uncovered_items(built, results, cases)

      {
        "summary" => summary_section(summary, results),
        "affected_modules" => Array(summary["affected_modules"]).presence || cases.map { |c| built.catalog[c["screen_key"]]&.menu_name }.compact.uniq,
        "test_cases" => cases.reject { |c| c["case_type"] == "regression" },
        "regression_cases" => cases.select { |c| c["case_type"] == "regression" }.map { |c| c.except("case_type") },
        "pass_criteria" => Array(summary["pass_criteria"]),
        "manual_checks" => (results.reject(&:error).flat_map { |r| Array(r.data["manual_checks"]) } + Array(summary["manual_checks"])).uniq,
        "uncertain_items" => uncertain,
        "preparation" => results.reject(&:error).flat_map { |r| Array(r.data["preparation"]) }.uniq.first(12),
        "screen_map" => screen_map(built),
        "batches" => results.map { |r| batch_meta(r) },
      }
    end

    def normalize_case(c, catalog)
      screen = catalog[c["screen_key"]]
      c.slice("name", "case_type", "impact_item_refs", "screen_key", "verification_purpose", "steps", "expected_result", "failure_criteria", "notes")
       .merge("page_path" => screen&.page_path, "evidence" => Array(c["evidence"]).presence || Array(c["impact_item_refs"]))
    end

    def summary_section(summary, results)
      title = summary.dig("summary", "title").presence || pull_request_analysis.pr_title.presence || "PR ##{pull_request_analysis.pr_number}"
      changes = Array(summary.dig("summary", "changes")).presence ||
                results.reject(&:error).flat_map { |r| Array(r.data["chunk_summary"]) }.first(8)
      { "title" => title, "changes" => changes }
    end

    # A batch can only speak for its own screens: "can't be verified on this
    # screen" is noise once another batch did write a case for that ref, so
    # covered refs are dropped and items left with none are omitted.
    def batch_uncertain_items(results, cases)
      covered = cases.flat_map { |c| c["impact_item_refs"] }.to_set
      results.reject(&:error).flat_map { |r| Array(r.data["uncertain_items"]) }.filter_map do |item|
        refs = Array(item["refs"])
        next item if refs.empty?

        remaining = refs.reject { |ref| covered.include?(ref) }
        item.merge("refs" => remaining) if remaining.any?
      end
    end

    def failed_batch_items(results)
      results.select(&:error).map do |r|
        { "description" => "「#{r.chunk.title}」這批畫面的測試步驟產生失敗", "reason" => r.error, "refs" => r.chunk.refs }
      end
    end

    # The coverage guarantee: every ref must end up in a case, an explained
    # uncertain item, or a deterministic note — anything left is listed.
    def uncovered_items(built, results, cases)
      accounted = cases.flat_map { |c| c["impact_item_refs"] } +
                  results.reject(&:error).flat_map { |r| Array(r.data["uncertain_items"]).flat_map { |i| Array(i["refs"]) } } +
                  built.deterministic_items.flat_map { |i| i["refs"] } +
                  results.select(&:error).flat_map { |r| r.chunk.refs }
      (built.ref_index.keys - accounted).map do |ref|
        info = built.ref_index[ref]
        screens = info[:screen_keys].first(3).filter_map { |k| built.catalog[k]&.display_name }
        {
          "description" => "#{info[:subject]} 尚未產生測試步驟",
          "reason" => screens.any? ? "系統判斷會影響：#{screens.join('、')}；請依此畫面補充驗證" : ScreenImpactLocator::BUCKET_LABELS.fetch(info[:bucket].to_s, "無法自動對應畫面"),
          "refs" => [ ref ],
        }
      end
    end

    def screen_map(built)
      built.mappings.map do |m|
        {
          "ref" => m.ref, "subject" => m.subject, "file" => m.changed_file&.file_path,
          "category" => m.bucket && ScreenImpactLocator::BUCKET_LABELS[m.bucket],
          "screens" => m.screen_keys.filter_map { |k| built.catalog[k]&.page_path },
          "trace" => m.trace,
        }
      end
    end

    def batch_meta(result)
      {
        "key" => result.chunk.key, "title" => result.chunk.title, "refs" => result.chunk.refs.size,
        "input_tokens" => result.responses.sum { |r| r.input_tokens.to_i },
        "output_tokens" => result.responses.sum { |r| r.output_tokens.to_i },
        "cost_usd" => usage_cost_usd(result.responses)&.to_f,
        "duration_ms" => result.duration_ms, "repaired" => result.repaired, "supplemented" => result.supplemented, "error" => result.error,
      }.compact
    end

    # --- persistence ----------------------------------------------------------

    def persist(data, built)
      report = nil

      PullRequestAnalysis.transaction do
        report = pull_request_analysis.test_reports.create!(
          title: data.dig("summary", "title"),
          summary: Array(data.dig("summary", "changes")).map { |c| "#{c['type']}：#{c['description']}" }.join("\n"),
          structured_content: data,
          status: "completed",
          generated_by: "llm",
          **usage_attributes,
          prompt_version: TEST_SCOPE_PROMPT_VERSION,
          skill_version: TestScopePrompt::SKILL_VERSION,
          schema_version: TestScopeSchema::VERSION,
          evidence_hash: EvidenceHash.call(built.chunks.map(&:input)),
          temperature: LlmConfig.temperature,
        )

        all_cases = data["test_cases"] + data["regression_cases"].map { |c| c.merge("case_type" => "regression") }
        all_cases.each_with_index { |c, i| create_test_case(report, c, i + 1, built) }
      end

      report
    end

    def create_test_case(report, c, position, built)
      report.test_cases.create!(
        business_feature: feature_for_screen(c["screen_key"]),
        impact_item_id: Array(c["impact_item_refs"]).filter_map { |ref| built.ref_index.dig(ref, :impact_item_id) }.first,
        case_type: c["case_type"],
        position: position,
        name: c["name"],
        page_path: c["page_path"],
        verification_purpose: c["verification_purpose"],
        steps: c["steps"],
        expected_result: c["expected_result"],
        failure_criteria: c["failure_criteria"],
        notes: c["notes"],
        evidence: c["evidence"],
      )
    end

    # --- usage / cost --------------------------------------------------------

    # Every provider response, from any batch thread, retries included — what
    # was actually billed, not just what ended up in the report.
    def track_usage(response)
      @usage_lock.synchronize { @usage << response }
    end

    def usage_attributes
      first = @usage.first
      {
        llm_provider: first&.provider,
        llm_model: first&.model,
        input_tokens: @usage.sum { |r| r.input_tokens.to_i },
        cached_input_tokens: @usage.sum { |r| r.cached_input_tokens.to_i },
        output_tokens: @usage.sum { |r| r.output_tokens.to_i },
        estimated_cost_usd: usage_cost_usd(@usage),
        pricing: first && { "model" => first.model, "usd_per_million_tokens" => Pricing.for(first.model),
                            "usd_twd_rate" => Pricing.usd_to_twd_rate&.to_f }.compact,
        duration_ms: elapsed_ms(@started_at),
      }
    end

    # nil when any call's model has no known price — a partial sum would
    # understate the cost while looking complete.
    def usage_cost_usd(responses)
      costs = responses.map do |r|
        Pricing.cost_usd(model: r.model, input_tokens: r.input_tokens, cached_input_tokens: r.cached_input_tokens, output_tokens: r.output_tokens)
      end
      costs.include?(nil) ? nil : costs.sum(BigDecimal("0"))
    end

    # A run that fails after some calls already went through still cost
    # money; keep its usage as a failed report so the PR's total is honest.
    def record_failed_run(message)
      return if @usage.blank? || @usage.sum { |r| r.input_tokens.to_i + r.output_tokens.to_i }.zero?

      pull_request_analysis.test_reports.create!(
        status: "failed", error_message: message, generated_by: "llm",
        structured_content: { "error" => message },
        prompt_version: TEST_SCOPE_PROMPT_VERSION, skill_version: TestScopePrompt::SKILL_VERSION,
        schema_version: TestScopeSchema::VERSION, temperature: LlmConfig.temperature,
        **usage_attributes,
      )
    rescue StandardError => e
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] could not record failed run usage: #{e.message}")
    end

    # The business feature named for the screen's own controller action.
    def feature_for_screen(screen_key)
      return nil if screen_key.blank?

      controller_path, action = screen_key.split("#", 2)
      features_by_action["#{controller_path.camelize}Controller##{action}"]
    end

    def features_by_action
      @features_by_action ||= FeatureCodeEntity.joins(:business_feature).where(business_features: { project_id: project.id })
        .includes(:business_feature, :code_entity).select { |fce| fce.role == "controller_action" }
        .to_h { |fce| [ "#{fce.code_entity.class_name}##{fce.code_entity.method_name}", fce.business_feature ] }
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_now - started_at) * 1000).round
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "llm_failed", error_message: message, error_stage: "llm_analyzing")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
