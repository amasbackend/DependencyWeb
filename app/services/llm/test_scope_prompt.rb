module Llm
  # Turns TestScopeInputBuilder's per-batch input into the two strings
  # Llm::Provider#generate expects. A PR is no longer sent in one request:
  # each batch (one group of screens plus only the changes traced to them)
  # gets its own call with the rules in skills/test_scope/skill.md, and one
  # final, small call (skills/test_scope/summary.md) writes the report's
  # overview from the batches' results. Both prompt files are a YAML
  # `version:` frontmatter followed by the exact prompt body, verbatim.
  class TestScopePrompt
    SKILL_PATH = Rails.root.join("skills", "test_scope", "skill.md")
    SUMMARY_PATH = Rails.root.join("skills", "test_scope", "summary.md")

    def self.load_skill(path)
      _blank, frontmatter, body = File.read(path).split(/^---\s*\n/, 3)
      [ YAML.safe_load(frontmatter).fetch("version").freeze, body.freeze ]
    end

    SKILL_VERSION, SYSTEM_PROMPT = load_skill(SKILL_PATH)
    _summary_version, SUMMARY_PROMPT = load_skill(SUMMARY_PATH)

    def self.build(chunk_input)
      { system: SYSTEM_PROMPT, user: chunk_user_prompt(chunk_input) }
    end

    def self.build_summary(summary_input)
      { system: SUMMARY_PROMPT, user: section("總覽輸入", summary_input) }
    end

    # Appended to a batch's prompt when its first answer failed validation —
    # the model gets told exactly what was wrong instead of a blind retry.
    def self.repair_note(errors)
      "\n\n## 上一次的輸出有以下問題，請修正後重新輸出完整 JSON\n#{errors.map { |e| "- #{e}" }.join("\n")}"
    end

    # Appended when a valid batch answer still left some refs unaddressed —
    # asks only for those, listing what was already written so it isn't
    # repeated.
    def self.supplement_note(existing_case_names, missing_refs)
      <<~NOTE

        ## 補充要求
        上一次的輸出已採用，已產生的案例：#{existing_case_names.presence&.join('、') || '（無）'}。
        但以下代號尚未交代：#{missing_refs.join('、')}。
        請只針對這些代號輸出補充 JSON（同樣的結構）：能寫成畫面操作的放進 test_cases，不能的放進 uncertain_items 並說明原因。不要重複上面已產生的案例。
      NOTE
    end

    def self.chunk_user_prompt(input)
      [
        section("PR 資訊", input[:pull_request]),
        section("畫面清單（screens）", input[:screens]),
        section("異動清單（changes）", input[:changes]),
        section("程式差異片段（diffs）", input[:diffs]),
        section("欄位中文對照（glossary）", input[:glossary]),
        input[:note].presence,
      ].compact.join("\n\n")
    end

    def self.section(title, value)
      "## #{title}\n#{JSON.pretty_generate(value)}"
    end

    private_class_method :chunk_user_prompt, :section
  end
end
