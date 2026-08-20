module Llm
  # §32-37: turns this PR's already-computed evidence (Phases 8-11 — diff,
  # Graphify graph, impact classification) into an operator-facing test
  # scope report. The LLM never sees the repository itself (§34/§62) and
  # never decides *which* code entities/features are impacted — that's
  # already been decided deterministically; its job is purely the §35
  # translation into operator language, grounded in real impact_item
  # references it must cite (§36).
  class AnalyzeTestScope < Actor
    input :pull_request_analysis
    output :test_report

    def call
      pull_request_analysis.update!(status: "llm_analyzing")

      built = TestScopeInputBuilder.call(pull_request_analysis)
      prompt = TestScopePrompt.build(built.input)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Provider.current.generate(system: prompt[:system], prompt: prompt[:user], json: true)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      data = response.parsed_json
      errors = TestScopeSchema.validate(data)
      raise TestScopeSchema::ValidationError, errors.join("; ") if errors.any?

      self.test_report = persist(response, data, duration_ms, built.ref_to_impact_item_id)
    rescue StandardError => e
      fail_with(I18n.t("actor.llm.analyze_test_scope.failed", message: e.message))
    end

    private

    def persist(response, data, duration_ms, ref_to_impact_item_id)
      report = nil

      PullRequestAnalysis.transaction do
        report = pull_request_analysis.test_reports.create!(
          title: data.dig("summary", "title"),
          summary: summary_text(data),
          structured_content: data,
          status: "completed",
          generated_by: "llm",
          llm_provider: response.provider,
          llm_model: response.model,
          prompt_version: TEST_SCOPE_PROMPT_VERSION,
          input_tokens: response.input_tokens,
          output_tokens: response.output_tokens,
          duration_ms: duration_ms,
        )

        all_cases = data.fetch("test_cases", []) +
          data.fetch("regression_cases", []).map { |c| c.merge("case_type" => "regression") }
        all_cases.each_with_index { |c, index| create_test_case(report, c, index + 1, ref_to_impact_item_id) }
      end

      report
    end

    def create_test_case(report, c, position, ref_to_impact_item_id)
      report.test_cases.create!(
        business_feature: resolve_feature(c["feature"]),
        impact_item_id: resolve_impact_item_id(c["impact_item_refs"], ref_to_impact_item_id),
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

    # feature is constrained to a known vocabulary (TestScopePrompt's rule
    # #2) — a name that still doesn't resolve is logged, not fatal to the
    # whole report; the case is kept with business_feature left nil rather
    # than discarding real test steps over one bad label.
    def resolve_feature(name)
      return nil if name.blank?

      feature = pull_request_analysis.project.business_features.find_by(name: name)
      Rails.logger.warn("[PRAnalysis:#{pull_request_analysis.id}] LLM cited unknown feature #{name.inspect}") unless feature
      feature
    end

    def resolve_impact_item_id(refs, ref_to_impact_item_id)
      Array(refs).filter_map { |ref| ref_to_impact_item_id[ref] }.first
    end

    def summary_text(data)
      Array(data.dig("summary", "changes")).map { |c| "#{c['type']}：#{c['description']}" }.join("\n")
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "llm_failed", error_message: message, error_stage: "llm_analyzing")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
