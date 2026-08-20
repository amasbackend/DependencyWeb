require "test_helper"

class Projects::PullRequestAnalysesControllerTest < ActionDispatch::IntegrationTest
  test "create with a valid PR number starts an analysis and redirects to it" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    enqueued = false

    PullRequestAnalysisJob.stub :perform_later, ->(**) { enqueued = true } do
      post project_pull_request_analyses_path(project), params: { pr_number: "65" }
    end

    analysis = project.pull_request_analyses.find_by(pr_number: 65)
    assert_redirected_to project_pull_request_analysis_path(project, analysis)
    assert_not_nil flash[:notice]
    assert enqueued
  end

  test "create with a non-integer PR number redirects back with an alert and creates nothing" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    post project_pull_request_analyses_path(project), params: { pr_number: "65abc" }

    assert_redirected_to project_path(project)
    assert_not_nil flash[:alert]
    assert_not project.pull_request_analyses.exists?
  end

  test "show renders the analysis, including a base-branch mismatch warning when relevant" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "master", status: "ready")
    analysis = project.pull_request_analyses.create!(
      pr_number: 65, status: "fetching_pr", pr_title: "修正問題", base_branch: "test/i18n"
    )

    get project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match "修正問題", response.body
    assert_match(/Base Branch/, response.body)
  end

  test "show defaults to the test_scope tab, not raw diff or changes (§42)" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")

    get project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match(/class="active"[^>]*>測試範圍/, response.body)
  end

  test "an unrecognized tab param falls back to test_scope rather than erroring" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65)

    get project_pull_request_analysis_path(project, analysis, tab: "nonsense")

    assert_response :success
    assert_match(/class="active"[^>]*>測試範圍/, response.body)
  end

  test "business tab groups impact items by risk level, with and without a mapped business feature" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    code_entity = project.code_entities.create!(
      entity_type: "model", name: "Order", class_name: "Order",
      file_path: "app/models/order.rb", signature_hash: "sig-1",
    )
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    analysis.impact_items.create!(
      code_entity: code_entity, business_feature: feature, impact_level: "direct_change", reason: "此 PR 直接修改：Order",
    )
    analysis.impact_items.create!(impact_level: "indirect_dependency", needs_manual_review: true)

    get project_pull_request_analysis_path(project, analysis, tab: "business")

    assert_response :success
    assert_match "高風險", response.body
    assert_match "中風險", response.body
    assert_match "出貨", response.body
    assert_match "需要人工確認", response.body
  end

  test "technical tab shows changed code entities grouped by type and impact items by graph dependency" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    code_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-2",
    )
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    changed_file = analysis.changed_files.create!(file_path: "app/actors/orders/ship.rb", change_type: "modified")
    analysis.changed_code_entities.create!(
      changed_file: changed_file, code_entity: code_entity, entity_type: "actor",
      class_name: "Orders::Ship", method_name: "call", change_kind: "modified",
    )
    analysis.impact_items.create!(code_entity: code_entity, impact_level: "direct_change")

    get project_pull_request_analysis_path(project, analysis, tab: "technical")

    assert_response :success
    assert_match "Orders::Ship#call", response.body
    assert_match "直接修改", response.body
  end

  test "raw_diff tab shows the full patch for each changed file" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")
    analysis.changed_files.create!(
      file_path: "app/models/order.rb", change_type: "modified", patch: "@@ -1,1 +1,1 @@\n-old\n+new\n",
    )

    get project_pull_request_analysis_path(project, analysis, tab: "raw_diff")

    assert_response :success
    assert_match "@@ -1,1 +1,1 @@", response.body
  end

  test "show renders the latest test report's cases and pass criteria" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "llm_analyzing")
    report = analysis.test_reports.create!(
      title: "修正出貨數量", summary: "修正出貨計算錯誤",
      structured_content: { "pass_criteria" => [ "儲存成功" ], "manual_checks" => [], "uncertain_items" => [] },
      status: "completed", llm_provider: "gemini", llm_model: "gemini-2.5-flash", prompt_version: "v1",
    )
    report.test_cases.create!(
      case_type: "core_change", position: 1, name: "出貨儲存驗證",
      verification_purpose: "確認出貨可正常儲存", steps: [ "填寫數量", "按儲存" ], expected_result: "儲存成功",
    )

    get project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match "出貨儲存驗證", response.body
    assert_match "確認出貨可正常儲存", response.body
    assert_match "測試通過標準", response.body
  end

  test "show renders the rendered markdown report when present" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "completed")
    analysis.test_reports.create!(
      title: "修正出貨數量", structured_content: { "x" => 1 }, status: "completed", prompt_version: "v1",
      markdown_content: "# 修正出貨數量 — 測試範圍報告\n\n## 修改摘要\n",
    )

    get project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match "完整測試範圍報告", response.body
    assert_match "# 修正出貨數量 — 測試範圍報告", response.body
  end

  test "report downloads the markdown content as a file attachment (§78 step 15)" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "completed")
    analysis.test_reports.create!(
      title: "修正出貨數量", structured_content: { "x" => 1 }, status: "completed", prompt_version: "v1",
      markdown_content: "# 修正出貨數量 — 測試範圍報告\n",
    )

    get report_project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/PR65-test-scope\.md/, response.headers["Content-Disposition"])
    assert_equal "# 修正出貨數量 — 測試範圍報告\n", response.body
  end

  test "report redirects with an alert when no report has been generated yet" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")

    get report_project_pull_request_analysis_path(project, analysis)

    assert_redirected_to project_pull_request_analysis_path(project, analysis)
    assert_not_nil flash[:alert]
  end
end
