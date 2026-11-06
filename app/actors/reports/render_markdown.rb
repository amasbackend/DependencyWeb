module Reports
  # §39: renders Reports::Build's view data into the exact document shape
  # confirmed against spec_sample.md — 修改摘要 → 操作頁面↔驗證目的對照總表 →
  # 測試前準備 → 各模組測試步驟 (per case: 頁面/驗證內容/操作步驟/預期結果/
  # 失敗判讀/注意事項) → 測試通過標準 → 建議測試順序 → 附錄. Pure templating —
  # every value rendered here was already validated (Phase 12's schema) or
  # computed deterministically (Reports::Build); this actor doesn't decide
  # content, only formats it.
  class RenderMarkdown < Actor
    input :pull_request_analysis
    input :test_report
    input :report_data
    output :markdown

    def call
      self.markdown = render_document
      test_report.update!(markdown_content: markdown)
      pull_request_analysis.update!(status: "completed")
    rescue StandardError => e
      fail_with(I18n.t("actor.reports.render_markdown.failed", message: e.message))
    end

    private

    def render_document
      [
        header, changes_section, overview_section, preparation_section,
        cases_section, pass_criteria_section, suggested_order_section,
        uncertain_items_section, screen_map_section, appendix_section,
      ].compact.join("\n\n---\n\n")
    end

    def header
      <<~MD.strip
        # #{test_report.title} — 測試範圍報告

        > 對應 PR：##{pull_request_analysis.pr_number}（#{pull_request_analysis.pr_title}）
        > 分析產生：#{test_report.created_at.strftime('%Y-%m-%d %H:%M')}（UTC+8） · LLM：#{test_report.llm_provider}/#{test_report.llm_model} · Prompt #{test_report.prompt_version}
        > 視角：**現場操作人員／測試人員**
      MD
    end

    def changes_section
      rows = report_data[:summary_changes].map { |c| "| #{cell(c['type'])} | #{cell(c['description'])} |" }
      <<~MD.strip
        ## 修改摘要

        | 類型 | 說明 |
        |------|------|
        #{rows.any? ? rows.join("\n") : "| （無） | （無） |"}
      MD
    end

    def overview_section
      rows = report_data[:overview_rows].map do |r|
        "| #{cell(r[:scenario])} | #{cell(r[:page_path] || '（未知）')} | #{cell(r[:action_summary])} | #{cell(r[:verification_purpose])} |"
      end
      <<~MD.strip
        ## 操作頁面 ↔ 驗證目的對照總表

        | 場景 | 代表頁面 | 操作人員動作 | 驗證目的 |
        |------|---------|-------------|---------|
        #{rows.any? ? rows.join("\n") : "| （無測試案例） | | | |"}
      MD
    end

    def preparation_section
      <<~MD.strip
        ## 測試前準備（操作人員）

        #{numbered_list(report_data[:preparation], fallback: "（無特別需準備事項）")}
      MD
    end

    def cases_section
      sections = report_data[:cases].each_with_index.map { |c, i| case_subsection(c, i + 1) }
      <<~MD.strip
        ## 各模組測試步驟

        #{sections.any? ? sections.join("\n\n---\n\n") : "（此次分析未產生具體測試案例，詳見「需要人工確認」章節）"}
      MD
    end

    def case_subsection(test_case, index)
      rows = [
        [ "頁面", test_case.page_path || "（未知）" ],
        [ "驗證內容", test_case.verification_purpose ],
        [ "操作步驟", numbered_inline(test_case.steps) ],
        [ "預期結果", test_case.expected_result ],
      ]
      rows << [ "失敗判讀", test_case.failure_criteria ] if test_case.failure_criteria.present?
      rows << [ "注意事項", test_case.notes ] if test_case.notes.present?

      table = rows.map { |label, value| "| **#{label}** | #{cell(value)} |" }.join("\n")

      <<~MD.strip
        ### #{index}. #{test_case.name}（#{test_case.case_type_text}#{test_case.business_feature ? " · #{test_case.business_feature.name}" : ""}）

        | 項目 | 內容 |
        |------|------|
        #{table}
      MD
    end

    def pass_criteria_section
      <<~MD.strip
        ## 測試通過標準

        #{bullet_list(report_data[:pass_criteria], fallback: "（無）")}

        #{report_data[:manual_checks].any? ? "### 建議人工額外檢查\n\n#{bullet_list(report_data[:manual_checks])}" : ""}
      MD
    end

    def suggested_order_section
      lines = report_data[:suggested_order_groups].each_with_index.map do |(case_type, group_cases), i|
        refs = report_data[:cases].each_with_index.filter_map { |c, idx| "#{idx + 1}（#{c.name}）" if c.case_type == case_type }
        "#{i + 1}. **#{group_cases.first.case_type_text}**：案例 #{refs.join(' → ')}"
      end
      <<~MD.strip
        ## 建議測試順序

        #{lines.any? ? lines.join("\n") : "（無）"}
      MD
    end

    def uncertain_items_section
      items = report_data[:uncertain_items]
      return nil if items.blank?

      lines = items.map do |item|
        refs = Array(item["refs"]).presence
        "- **#{item['description']}**#{refs ? "（#{refs.join('、')}）" : ''} — #{item['reason']}"
      end
      <<~MD.strip
        ## 需要人工確認

        以下項目因證據不足，無法由本系統自動判定測試範圍，請工程或資訊人員協助確認：

        #{lines.join("\n")}
      MD
    end

    # Which screen each change was traced to, and why — computed by
    # ScreenImpactLocator, not the LLM, so testers and engineers can check
    # the mapping itself.
    def screen_map_section
      rows = report_data[:screen_map]
      return nil if rows.blank?

      lines = rows.map do |r|
        target = r["screens"].presence&.first(4)&.join("<br>") || r["category"] || "（無）"
        target += "<br>…等 #{r['screens'].size} 個畫面" if r["screens"].to_a.size > 4
        "| #{cell(r['ref'])} | #{cell(r['subject'])} | #{cell(target)} | #{cell(Array(r['trace']).first)} |"
      end
      <<~MD.strip
        ## 附錄：異動與畫面對照（系統依程式呼叫關係自動判斷）

        | 代號 | 異動項目 | 對應畫面／類別 | 判斷依據 |
        |------|---------|---------------|---------|
        #{lines.join("\n")}
      MD
    end

    def appendix_section
      <<~MD.strip
        ## 附錄：操作人員回報時請一併提供

        | 項目 | 說明 |
        |------|------|
        | PR 編號 | ##{pull_request_analysis.pr_number} |
        | 操作頁面／功能 | 實際操作的頁面路徑或功能名稱 |
        | 操作內容 | 第幾個案例、改前／改後內容、按下按鈕的時間 |
        | 畫面結果 | 成功／完整錯誤訊息原文（可截圖） |
        | 預期落差 | 例如「以為會看到 X，實際卻看到 Y」 |
      MD
    end

    def numbered_list(items, fallback: "（無）")
      return fallback if items.blank?

      items.each_with_index.map { |item, i| "#{i + 1}. #{item}" }.join("\n")
    end

    def numbered_inline(items)
      Array(items).each_with_index.map { |step, i| "#{i + 1}. #{step}" }.join("<br>")
    end

    def bullet_list(items, fallback: "（無）")
      return fallback if items.blank?

      items.map { |item| "- #{item}" }.join("\n")
    end

    # Markdown table cells break on a literal "|" or newline — sanitize
    # rather than let real (LLM-authored) content silently corrupt the table.
    def cell(text)
      text.to_s.gsub("|", "\\|").gsub("\n", "<br>")
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "building_report")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
