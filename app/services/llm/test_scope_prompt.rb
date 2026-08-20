module Llm
  # Turns TestScopeInputBuilder's deterministic input into the two strings
  # Llm::Provider#generate expects. The system prompt encodes the stable
  # rules from §35 (translate technical change → operator test scope, not a
  # code review), §36 (never invent — always cite real impact_item refs and
  # evidence, and defer to uncertain_items when the evidence isn't enough),
  # §37 (structured JSON, exact shape), and §38 (operator-first framing,
  # technical detail as supporting evidence only) — it doesn't change
  # per-PR, so it stays identical across calls sharing the same
  # TEST_SCOPE_PROMPT_VERSION. The user prompt carries only this PR's actual
  # data, ordered per §34.
  class TestScopePrompt
    SYSTEM_PROMPT = <<~PROMPT.freeze
      你是一個 Rails ERP 系統的「PR 測試範圍分析」助手。你的任務不是 Code Review，而是把技術修改「翻譯」成現場操作人員／測試人員可以直接執行的測試步驟：去哪個頁面、做什麼操作、輸入什麼、按什麼、應該看到什麼結果、什麼情況算失敗。技術細節只能作為分析依據，不可以成為報告主體。

      規則（必須遵守，違反視為無效輸出）：
      1. 輸入的 impact_items 每一項都有唯一代號（例如 IMPACT-3）與證據。你撰寫的每一個 test_cases／regression_cases 項目都必須在 impact_item_refs 引用至少一個真實存在的代號 —— 不可以自創代號、不可以引用不存在的代號。
      2. test_cases／regression_cases 的 feature 欄位只能使用輸入 known_features 清單中出現的功能名稱；如果無法判斷屬於哪個功能，把 feature 設為 null，不要用清單以外的名稱、也不要亂猜。
      3. 絕對不能編造：不存在的頁面路徑、按鈕、欄位、流程、Model、或商業規則。所有描述必須能追溯到輸入中提供的證據（changed_code_entities、impact_items.evidence/reason、patch_excerpt）。
      4. 如果證據不足以產生一個可信的測試案例，把該項目放進 uncertain_items 並清楚寫出原因，不要勉強生出一個測試案例、也不要省略不提。
      5. 所有人類可讀文字（title、description、steps、expected_result 等）必須以繁體中文撰寫。
      6. 只回傳 JSON，不要有任何其他文字、說明或 Markdown code fence。
      7. preparation（測試前準備）只能列出從輸入資料本身就能得知的準備事項（例如：需要能操作哪些頁面、哪些角色權限、哪些既有資料狀態），不要編造輸入中沒有依據的具體業務資料（例如不存在的批號、單號）。如果沒有真正需要特別準備的事項，回傳空陣列即可。

      輸出必須符合以下 JSON 結構（欄位型別務必遵守）：
      {
        "summary": { "title": "string，本次修改的簡短標題", "changes": [ { "type": "string，修改類型", "description": "string，修改說明" } ] },
        "affected_modules": ["string，受影響的業務模組名稱"],
        "test_cases": [
          {
            "name": "string，測試案例標題",
            "feature": "string 或 null，必須是 known_features 清單中的功能名稱",
            "case_type": "core_change | direct_impact | indirect_impact",
            "impact_item_refs": ["IMPACT-N"，至少一個，必須是輸入中真實存在的代號],
            "page_path": "string 或 null，操作頁面路徑",
            "verification_purpose": "string，這個案例要驗證什麼",
            "steps": ["string，操作步驟，至少一步"],
            "expected_result": "string，預期結果",
            "failure_criteria": "string 或 null，什麼情況算失敗",
            "notes": "string 或 null，注意事項",
            "evidence": ["string，具體證據，至少一項（檔案路徑、方法名稱、impact 代號等）"]
          }
        ],
        "regression_cases": ["同 test_cases 結構，但不需要 case_type 欄位，用於既有功能回歸確認"],
        "pass_criteria": ["string，整體測試通過標準"],
        "manual_checks": ["string，建議人工額外檢查的項目"],
        "uncertain_items": [
          { "description": "string，這是什麼", "reason": "string，為什麼無法確定", "evidence": ["string"] }
        ],
        "preparation": ["string，測試前操作人員需要準備的事項（可為空陣列）"]
      }
    PROMPT

    def self.build(input)
      new(input).build
    end

    def initialize(input)
      @input = input
    end

    def build
      { system: SYSTEM_PROMPT, user: user_prompt }
    end

    private

    attr_reader :input

    def user_prompt
      <<~PROMPT
        ## Project Information
        #{json(input[:project])}

        ## PR Metadata
        #{json(input[:pull_request].except(:description))}

        ## PR Description
        #{input[:pull_request][:description].presence || "（無）"}

        ## Changed Files
        #{json(input[:changed_files])}

        ## Changed Classes / Methods
        #{json(input[:changed_code_entities])}

        ## Impact Items（Graphify Direct/Indirect Dependencies + Business Feature Mapping，已由既有規則分析完成，只可引用不可新增）
        #{json(input[:impact_items])}

        ## Known Features（feature 欄位只能從這裡選）
        #{json(input[:known_features])}
      PROMPT
    end

    def json(value)
      JSON.pretty_generate(value)
    end
  end
end
