module Llm
  # Splits one PR's evidence into LLM-sized batches, one per group of screens
  # (ScreenCatalog), each carrying only the changes ScreenImpactLocator traced
  # to those screens plus their diff hunks and the screens' real on-screen
  # labels. This replaces sending everything in one request — which forced
  # hard caps (the old 30-impact-item / 5-patch limit) that silently dropped
  # evidence on large PRs, and gave the model no way to know which screen a
  # code change surfaces on.
  #
  # Every change gets a ref (CHG-n per changed class/method, FILE-n per other
  # changed file). Changes that can't reach a screen go to a separate "other"
  # batch; ones needing no LLM at all (dev-only files, code nothing calls) are
  # returned as deterministic_items. Either way every ref ends up accounted
  # for — see Llm::AnalyzeTestScope's coverage check.
  class TestScopeInputBuilder
    Chunk = Struct.new(:key, :title, :screen_keys, :refs, :input, keyword_init: true)
    Result = Struct.new(:chunks, :mappings, :catalog, :deterministic_items, :ref_index, keyword_init: true)

    # Rough per-batch size budget (characters of JSON). gpt-4.1-class models
    # take far more, but a focused batch produces better steps than a huge one.
    MAX_CHUNK_CHARS = 60_000
    MAX_DIFF_CHARS_PER_CHUNK = 36_000
    MAX_DIFF_CHARS_PER_FILE = 5_000
    MAX_LABELS_PER_SCREEN = 90
    DETERMINISTIC_BUCKETS = %w[dev_only unreferenced].freeze

    def self.call(pull_request_analysis, snapshot:)
      new(pull_request_analysis, snapshot).call
    end

    def initialize(pull_request_analysis, snapshot)
      @pull_request_analysis = pull_request_analysis
      @snapshot = snapshot
    end

    def call
      @catalog = ScreenCatalog.call(snapshot: snapshot)
      @mappings = ScreenImpactLocator.call(pull_request_analysis: pull_request_analysis, snapshot: snapshot, catalog: catalog)

      screen_mappings = mappings.select { |m| m.bucket.nil? }
      llm_other = mappings.reject { |m| m.bucket.nil? || DETERMINISTIC_BUCKETS.include?(m.bucket) }

      chunks = screen_chunks(screen_mappings)
      chunks += other_chunks(llm_other) if llm_other.any?

      Result.new(
        chunks: chunks, mappings: mappings, catalog: catalog,
        deterministic_items: deterministic_items, ref_index: ref_index,
      )
    end

    private

    attr_reader :pull_request_analysis, :snapshot, :catalog, :mappings

    # Screens grouped by controller (a module's list/new/edit/show belong in
    # one batch so the model sees the whole flow), split per screen when a
    # group would exceed the size budget.
    def screen_chunks(screen_mappings)
      by_screen = Hash.new { |h, k| h[k] = [] }
      screen_mappings.each { |m| m.screen_keys.each { |key| by_screen[key] << m } }

      by_screen.keys.group_by { |key| catalog[key].controller_path }.flat_map do |controller_path, screen_keys|
        grouped = build_screen_chunk(controller_path, screen_keys, by_screen)
        next [ grouped ] if grouped.input.to_json.size <= MAX_CHUNK_CHARS

        screen_keys.map { |key| build_screen_chunk(key, [ key ], by_screen) }
      end
    end

    def build_screen_chunk(key, screen_keys, by_screen)
      chunk_mappings = screen_keys.flat_map { |k| by_screen[k] }.uniq(&:ref).sort_by { |m| ref_sort_key(m.ref) }
      screens = screen_keys.map { |k| catalog[k] }

      Chunk.new(
        key: key,
        title: screens.map(&:display_name).uniq.join("、"),
        screen_keys: screen_keys,
        refs: chunk_mappings.map(&:ref),
        input: {
          pull_request: pr_info,
          screens: screens.map { |s| screen_info(s) },
          changes: chunk_mappings.map { |m| change_info(m, screen_keys) },
          diffs: diffs_for(chunk_mappings),
          glossary: glossary_for(chunk_mappings, screens),
        },
      )
    end

    # Changes with no single screen: shared code reaching many screens,
    # machine-side APIs, database/locale/config. The model gets the full
    # screen directory (names only) so it can point testers at a screen where
    # the effect is observable, or say why it can't.
    def other_chunks(other_mappings)
      directory = catalog.all.map { |s| { screen_key: s.key, name: s.display_name, url: s.url } }
      other_mappings.sort_by { |m| ref_sort_key(m.ref) }.each_slice(30).each_with_index.map do |slice, i|
        Chunk.new(
          key: "other-#{i + 1}",
          title: "共用程式與非畫面異動#{i.positive? ? "（#{i + 1}）" : ""}",
          screen_keys: catalog.screens.keys,
          refs: slice.map(&:ref),
          input: {
            pull_request: pr_info,
            screens: directory,
            changes: slice.map { |m| change_info(m, nil).merge(category: ScreenImpactLocator::BUCKET_LABELS[m.bucket]) },
            diffs: diffs_for(slice),
            glossary: glossary_for(slice, []),
            note: "## 這一批的特別說明\n這批異動沒有單一對應畫面，例如共用程式、機台端 API、資料庫或語系。請判斷操作人員能在哪個畫面觀察到效果（screen_key 只能從畫面清單選），寫成回歸或間接影響案例；如果畫面上觀察不到，請放進 uncertain_items 並說明原因。",
          },
        )
      end
    end

    def pr_info
      @pr_info ||= {
        number: pull_request_analysis.pr_number,
        title: pull_request_analysis.pr_title,
        description: pull_request_analysis.pr_description.to_s.truncate(2_000),
      }
    end

    def screen_info(screen)
      { screen_key: screen.key, name: screen.display_name, url: screen.url, labels: screen.labels.first(MAX_LABELS_PER_SCREEN) }
    end

    def change_info(mapping, chunk_screen_keys)
      cce = mapping.changed_code_entity
      file = mapping.changed_file
      info = { ref: mapping.ref, subject: mapping.subject }
      if cce
        info[:kind] = cce.entity_type_text
        info[:change] = cce.change_kind_text
        info[:validation_changed] = true if cce.validation_changed
        info[:association_changed] = true if cce.association_changed
      else
        info[:kind] = "檔案"
        info[:change] = file&.change_type_text
      end
      info[:file] = file&.file_path
      info[:screens] = chunk_screen_keys ? mapping.screen_keys & chunk_screen_keys : mapping.screen_keys.first(10)
      info[:trace] = mapping.trace if mapping.trace.any?
      info
    end

    # Per-file diff text, narrowed for a changed method to the hunks that
    # touch it; bounded per file and per batch. When something has to be cut
    # the batch says so explicitly rather than truncating silently.
    def diffs_for(chunk_mappings)
      by_file = chunk_mappings.select(&:changed_file).group_by(&:changed_file)
      budget = MAX_DIFF_CHARS_PER_CHUNK
      omitted = []

      diffs = by_file.filter_map do |file, file_mappings|
        text = excerpt_for(file, file_mappings)
        next if text.blank?

        if budget <= 0
          omitted << file.file_path
          next
        end

        text = text.truncate([ budget, MAX_DIFF_CHARS_PER_FILE ].min, omission: "\n…（此檔案其餘差異略）")
        budget -= text.size
        { refs: file_mappings.map(&:ref), file: file.file_path, diff: text }
      end

      diffs << { refs: [], file: "（篇幅限制）", diff: "以下檔案的差異未附上，請以 changes 的描述為準：#{omitted.join('、')}" } if omitted.any?
      diffs
    end

    def excerpt_for(file, file_mappings)
      hunks = file.patch.to_s.split(/(?=^@@ )/).select { |h| h.start_with?("@@") }
      return file.patch.to_s if hunks.empty?

      method_names = file_mappings.filter_map { |m| m.changed_code_entity&.method_name.presence }
      return hunks.join if method_names.empty? || file_mappings.any? { |m| m.changed_code_entity && m.changed_code_entity.method_name.blank? }

      pattern = /\b(?:#{method_names.map { |n| Regexp.escape(n) }.join('|')})\b/
      relevant = hunks.select { |h| h.match?(pattern) }
      (relevant.presence || hunks.first(2)).join
    end

    # Chinese model/attribute names from the target app's own zh-TW locale,
    # limited to the models a batch touches.
    def glossary_for(chunk_mappings, screens)
      return {} if locale_models.empty?

      names = chunk_mappings.flat_map { |m| [ m.changed_code_entity&.class_name.to_s.split("::").first ] } +
              screens.map { |s| s.controller_path.split("/").last.singularize.camelize }
      keys = names.compact_blank.map(&:underscore).uniq & locale_models.keys
      keys.to_h { |k| [ k, locale_models[k] ] }
    end

    def locale_models
      @locale_models ||= begin
        yaml = snapshot.paths.select { |p| p.start_with?("config/locales/") && p.end_with?(".yml") && p.include?("zh-TW") }
                       .filter_map { |p| YAML.safe_load(snapshot.read(p).to_s, aliases: true, permitted_classes: [ Symbol ]) rescue nil }
        activerecord = yaml.filter_map { |doc| doc.dig("zh-TW", "activerecord") }
        models = activerecord.map { |ar| ar["models"] || {} }.reduce({}, :merge)
        attributes = activerecord.map { |ar| ar["attributes"] || {} }.reduce({}, :merge)
        (models.keys | attributes.keys).to_h do |key|
          [ key, { name: models[key].is_a?(Hash) ? models[key]["one"] : models[key], attributes: attributes[key].is_a?(Hash) ? attributes[key].select { |_, v| v.is_a?(String) } : {} }.compact ]
        end
      end
    end

    # Unreferenced code is listed one by one (each is a question for an
    # engineer); dev-only files (specs, linters) are one line — a release
    # can carry dozens and they need no action at all.
    def deterministic_items
      unreferenced = mappings.select { |m| m.bucket == "unreferenced" }.map do |m|
        { "description" => "#{m.subject}（#{ScreenImpactLocator::BUCKET_LABELS['unreferenced']}）",
          "reason" => "目前程式中沒有任何地方呼叫它，畫面上不會有差異；請工程人員確認是否為預留或待移除的程式", "refs" => [ m.ref ] }
      end
      dev_only = mappings.select { |m| m.bucket == "dev_only" }
      return unreferenced if dev_only.empty?

      unreferenced + [ {
        "description" => "#{ScreenImpactLocator::BUCKET_LABELS['dev_only']} #{dev_only.size} 個檔案",
        "reason" => "例如 #{dev_only.first(3).map(&:subject).join('、')}；不影響操作，無需安排畫面測試",
        "refs" => dev_only.map(&:ref),
      } ]
    end

    # ref => { impact_item_id:, subject:, screen_keys:, bucket: }
    def ref_index
      direct_items = pull_request_analysis.impact_items.where(impact_level: "direct_change").pluck(:source_changed_code_entity_id, :id).to_h
      mappings.to_h do |m|
        [ m.ref, {
          impact_item_id: m.changed_code_entity && direct_items[m.changed_code_entity.id],
          subject: m.subject, screen_keys: m.screen_keys, bucket: m.bucket, trace: m.trace,
        } ]
      end
    end

    def ref_sort_key(ref)
      kind, number = ref.split("-")
      [ kind == "CHG" ? 0 : 1, number.to_i ]
    end
  end
end
