require "test_helper"

class Reports::RenderMarkdownTest < ActiveSupport::TestCase
  def build_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    pull_request_analysis = project.pull_request_analyses.create!(
      pr_number: 65, pr_title: "修正出貨數量", status: "building_report"
    )
    report = pull_request_analysis.test_reports.create!(
      title: "出貨修正", summary: "修正出貨計算",
      structured_content: {
        "summary" => { "changes" => [ { "type" => "bugfix", "description" => "修正計算" } ] },
        "pass_criteria" => [ "儲存成功" ], "manual_checks" => [ "確認庫存" ],
        "uncertain_items" => [ { "description" => "某項目", "reason" => "證據不足" } ],
        "preparation" => [ "準備測試帳號" ],
      },
      status: "completed", llm_provider: "gemini", llm_model: "gemini-2.5-flash", prompt_version: "v1",
    )
    report.test_cases.create!(
      business_feature: feature, case_type: "core_change", position: 1, name: "出貨儲存",
      page_path: "/orders/:id/ship", verification_purpose: "確認出貨可儲存",
      steps: [ "填數量", "按儲存" ], expected_result: "成功", failure_criteria: "顯示錯誤",
    )

    [ pull_request_analysis, report ]
  end

  test "renders the full document structure and persists it onto the report" do
    pra, report = build_scenario
    build_result = Reports::Build.result(pull_request_analysis: pra)
    assert build_result.success?

    result = Reports::RenderMarkdown.result(
      pull_request_analysis: pra, test_report: build_result.test_report, report_data: build_result.report_data
    )

    assert result.success?
    pra.reload
    assert_equal "completed", pra.status
    report.reload
    assert_equal result.markdown, report.markdown_content

    md = result.markdown
    assert_match "# 出貨修正", md
    assert_match "## 修改摘要", md
    assert_match "## 操作頁面 ↔ 驗證目的對照總表", md
    assert_match "## 測試前準備", md
    assert_match "準備測試帳號", md
    assert_match "## 各模組測試步驟", md
    assert_match "### 1. 出貨儲存", md
    assert_match "顯示錯誤", md
    assert_match "## 測試通過標準", md
    assert_match "## 建議測試順序", md
    assert_match "## 需要人工確認", md
    assert_match "某項目", md
    assert_match "## 附錄：操作人員回報時請一併提供", md
  end

  test "sanitizes pipe characters and newlines so LLM content can't break the markdown table" do
    pra, report = build_scenario
    report.test_cases.first.update!(verification_purpose: "含有 | 符號\n與換行的內容")
    build_result = Reports::Build.result(pull_request_analysis: pra)

    result = Reports::RenderMarkdown.result(
      pull_request_analysis: pra, test_report: build_result.test_report, report_data: build_result.report_data
    )

    assert result.success?
    assert_match "含有 \\| 符號<br>與換行的內容", result.markdown
  end

  test "omits the 需要人工確認 section entirely when there are no uncertain items" do
    pra, report = build_scenario
    report.update!(structured_content: report.structured_content.merge("uncertain_items" => []))
    build_result = Reports::Build.result(pull_request_analysis: pra)

    result = Reports::RenderMarkdown.result(
      pull_request_analysis: pra, test_report: build_result.test_report, report_data: build_result.report_data
    )

    assert result.success?
    assert_no_match(/需要人工確認/, result.markdown)
  end
end
