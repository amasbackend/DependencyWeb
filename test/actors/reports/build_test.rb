require "test_helper"

class Reports::BuildTest < ActiveSupport::TestCase
  def build_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65, status: "llm_analyzing")
    report = pull_request_analysis.test_reports.create!(
      title: "出貨修正", summary: "修正出貨數量計算",
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
      steps: [ "填數量", "按儲存" ], expected_result: "成功",
    )
    report.test_cases.create!(
      case_type: "regression", position: 2, name: "既有出貨不受影響",
      verification_purpose: "確認既有流程沒壞", steps: [ "檢查" ], expected_result: "正常",
    )

    pull_request_analysis
  end

  test "picks the latest completed report and assembles ordered view data" do
    pra = build_scenario

    result = Reports::Build.result(pull_request_analysis: pra)

    assert result.success?
    pra.reload
    assert_equal "building_report", pra.status

    data = result.report_data
    assert_equal 2, data[:overview_rows].size
    assert_equal "出貨儲存", data[:overview_rows].first[:scenario]
    assert_equal "填數量 → 按儲存", data[:overview_rows].first[:action_summary]
    assert_equal [ "準備測試帳號" ], data[:preparation]
    assert_equal [ "儲存成功" ], data[:pass_criteria]
    assert_equal 1, data[:uncertain_items].size

    # core_change sorts before regression per §31's priority order.
    assert_equal [ "core_change", "regression" ], data[:suggested_order_groups].map(&:first)
  end

  test "ignores a failed report and picks the latest completed one" do
    pra = build_scenario
    pra.test_reports.create!(
      title: "失敗嘗試", structured_content: { "x" => 1 }, status: "failed",
      prompt_version: "v1", error_message: "boom",
    )

    result = Reports::Build.result(pull_request_analysis: pra)

    assert result.success?
    assert_equal "出貨修正", result.test_report.title
  end

  test "fails cleanly when no completed report exists yet" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pra = project.pull_request_analyses.create!(pr_number: 65, status: "llm_analyzing")

    result = Reports::Build.result(pull_request_analysis: pra)

    assert_not result.success?
    pra.reload
    assert_equal "failed", pra.status
    assert_equal "building_report", pra.error_stage
  end
end
