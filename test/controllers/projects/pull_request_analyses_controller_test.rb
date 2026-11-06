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
    assert_select "nav a.border-blue-600", text: "測試範圍"
  end

  test "an unrecognized tab param falls back to test_scope rather than erroring" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65)

    get project_pull_request_analysis_path(project, analysis, tab: "nonsense")

    assert_response :success
    assert_select "nav a.border-blue-600", text: "測試範圍"
  end

  test "legacy tab names land on their merged tab" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")

    { "raw_diff" => "程式異動", "technical" => "影響範圍", "business" => "影響範圍", "graphify" => "影響範圍" }.each do |legacy, label|
      get project_pull_request_analysis_path(project, analysis, tab: legacy)

      assert_response :success
      assert_select "nav a.border-blue-600", text: label
    end
  end

  def build_impact_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    model = project.code_entities.create!(
      entity_type: "model", name: "Order", class_name: "Order", file_path: "app/models/order.rb", signature_hash: "sig-1",
    )
    caller_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-2",
    )
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    changed_file = analysis.changed_files.create!(file_path: "app/models/order.rb", change_type: "modified")
    changed = analysis.changed_code_entities.create!(
      changed_file: changed_file, code_entity: model, entity_type: "model", class_name: "Order", change_kind: "modified", validation_changed: true,
    )
    # Created out of order on purpose — rows must sort by risk, not id.
    analysis.impact_items.create!(source_changed_code_entity: changed, impact_level: "regression_candidate", needs_manual_review: true)
    analysis.impact_items.create!(source_changed_code_entity: changed, code_entity: caller_entity, business_feature: feature, impact_level: "indirect_dependency")
    analysis.impact_items.create!(source_changed_code_entity: changed, code_entity: model, impact_level: "direct_change", reason: "此 PR 直接修改：Order")
    [ project, analysis ]
  end

  test "impact tab groups dependents under the change they stem from, high to low risk, with business features" do
    project, analysis = build_impact_scenario

    get project_pull_request_analysis_path(project, analysis, tab: "impact")

    assert_response :success
    assert_select "nav a.border-blue-600", text: "影響範圍"
    assert_select "#impact-items details summary", text: /Order/
    assert_match "驗證變更", response.body
    assert_match "Orders::Ship#call", response.body
    assert_match "出貨", response.body
    assert_match "需要人工確認", response.body
    group = response.body[response.body.index('id="impact-items"')..]
    assert group.index("中風險") < group.index("低風險")
  end

  test "impact tab filters impact items by impact_level and preserves the filter in the select" do
    project, analysis = build_impact_scenario

    get project_pull_request_analysis_path(project, analysis, tab: "impact", impact_level: "indirect_dependency")

    assert_response :success
    assert_select "#impact-items tbody tr", count: 1
    assert_select "#impact-items tbody td", text: "間接依賴"
    assert_match(/<option selected="selected" value="indirect_dependency">/, response.body)
  end

  test "impact tab ignores an invalid impact_level filter value" do
    project, analysis = build_impact_scenario

    get project_pull_request_analysis_path(project, analysis, tab: "impact", impact_level: "not-a-real-level")

    assert_response :success
    assert_select "#impact-items tbody tr", count: 2
  end

  test "impact tab shows the test report's change-to-screen map" do
    project, analysis = build_impact_scenario
    analysis.test_reports.create!(
      title: "x", status: "completed", prompt_version: "v2",
      structured_content: { "screen_map" => [
        { "ref" => "CHG-1", "subject" => "Order", "screens" => [ "訂單管理 › 新增訂單（/orders/new）" ], "trace" => [ "Order → OrdersController#create" ] },
        { "ref" => "FILE-1", "subject" => "db/migrate/1_x.rb", "screens" => [], "category" => "資料庫結構／種子資料", "trace" => [] },
      ] },
    )

    get project_pull_request_analysis_path(project, analysis, tab: "impact")

    assert_response :success
    assert_select "#screen-map tbody tr", count: 2
    assert_match "訂單管理 › 新增訂單（/orders/new）", response.body
    assert_match "Order → OrdersController#create", response.body
    assert_match "資料庫結構／種子資料 1", response.body
  end

  def graphify_sample_graph
    {
      "nodes" => [
        { "id" => "a", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "_callable_class" => true, "community" => 0, "community_name" => "Ship" },
        { "id" => "a_call", "label" => ".call()", "source_file" => "app/actors/orders/ship.rb", "community" => 0, "community_name" => "Ship" },
        { "id" => "b_call", "label" => ".ship()", "source_file" => "app/controllers/orders_controller.rb", "community" => 1, "community_name" => "Controllers" },
      ],
      "links" => [
        { "source" => "a", "target" => "a_call", "relation" => "method" },
        { "source" => "b_call", "target" => "a_call", "relation" => "calls" },
      ],
    }
  end

  def build_graphify_analysis(graph: graphify_sample_graph)
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    analysis.graphify_artifacts.create!(format: "graph_json", raw_content: "{}", graphify_version: "0.0.0-test", parsed_content: graph)
    changed_file = analysis.changed_files.create!(file_path: "app/actors/orders/ship.rb", change_type: "modified")
    analysis.changed_code_entities.create!(
      changed_file: changed_file, entity_type: "actor", class_name: "Orders::Ship", method_name: "call", change_kind: "modified",
    )
    [ project, analysis ]
  end

  test "impact tab embeds Graphify's own graph.html for the PR subgraph next to the inspector" do
    project, analysis = build_graphify_analysis

    get project_pull_request_analysis_path(project, analysis, tab: "impact")

    assert_response :success
    assert_select "[data-controller=graphify-frame] iframe[src=?]", graph_project_pull_request_analysis_path(project, analysis, scope: "pr", depth: 2)
    assert_select "turbo-frame#graph-inspector"
  end

  test "graph renders Graphify's vis.js page for the PR subgraph with changed nodes highlighted" do
    project, analysis = build_graphify_analysis

    get graph_project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match "vis-network", response.body
    assert_match %r{const SEED_IDS = \["a_call"\]}, response.body
    assert_match %r{const DIRECT_IDS = \["b_call"\]}, response.body
    # The class node "a" is pulled in as a_call's structural parent.
    assert_match "3 nodes", response.body
  end

  test "graph with project scope renders the whole graph" do
    graph = graphify_sample_graph
    graph["nodes"] << { "id" => "unrelated", "label" => "Unrelated", "source_file" => "app/models/unrelated.rb", "_callable_class" => true }
    project, analysis = build_graphify_analysis(graph: graph)

    get graph_project_pull_request_analysis_path(project, analysis, scope: "project")

    assert_response :success
    assert_match "4 nodes", response.body
  end

  test "graph returns 404 when no graph.json artifact exists" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")

    get graph_project_pull_request_analysis_path(project, analysis)

    assert_response :not_found
  end

  test "impact tab's graph shows a not-found message when changed entities have no graph node" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    analysis.graphify_artifacts.create!(
      format: "graph_json", raw_content: "{}", graphify_version: "0.0.0-test",
      parsed_content: { "nodes" => [], "links" => [] },
    )
    changed_file = analysis.changed_files.create!(file_path: "app/models/new_thing.rb", change_type: "added")
    analysis.changed_code_entities.create!(
      changed_file: changed_file, entity_type: "model", class_name: "NewThing", change_kind: "added",
    )

    get project_pull_request_analysis_path(project, analysis, tab: "impact")

    assert_response :success
    assert_match "找不到對應節點", response.body
    assert_select "iframe", count: 0
  end

  test "impact tab's graph falls back to the empty state when no artifact exists" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")

    get project_pull_request_analysis_path(project, analysis, tab: "impact")

    assert_response :success
    assert_match "尚未取得", response.body
  end

  test "changes tab shows the full patch for each changed file" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")
    analysis.changed_files.create!(
      file_path: "app/models/order.rb", change_type: "modified", patch: "@@ -1,1 +1,1 @@\n-old\n+new\n",
    )

    get project_pull_request_analysis_path(project, analysis, tab: "changes")

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

  test "shows the latest completed report's cost and the PR's total across all runs, failed ones included" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "llm_failed")
    analysis.test_reports.create!(
      title: "第一次", structured_content: { "x" => 1 }, status: "completed", prompt_version: "v2", generated_by: "llm",
      llm_model: "gpt-4.1-2025-04-14", input_tokens: 1000, output_tokens: 100, estimated_cost_usd: 0.7, created_at: 2.minutes.ago,
    )
    analysis.test_reports.create!(
      structured_content: { "error" => "boom" }, status: "failed", prompt_version: "v2", generated_by: "llm",
      llm_model: "gpt-4.1-2025-04-14", input_tokens: 500, output_tokens: 0, estimated_cost_usd: 0.3,
    )

    with_env("LLM_USD_TWD_RATE" => "30") do
      get project_pull_request_analysis_path(project, analysis)
    end

    assert_response :success
    assert_match "第一次", response.body # the failed newer run doesn't replace the report shown
    assert_match "NT$21.00", response.body # this report: 0.7 × 30
    assert_match "NT$30.00", response.body # PR total: (0.7 + 0.3) × 30
    assert_match "共 2 次產生", response.body
  end

  test "shows the cost in US$ when no exchange rate is configured" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "completed")
    analysis.test_reports.create!(
      title: "x", structured_content: { "x" => 1 }, status: "completed", prompt_version: "v2", generated_by: "llm",
      llm_model: "gpt-4.1-2025-04-14", estimated_cost_usd: 0.7014,
    )

    with_env("LLM_USD_TWD_RATE" => nil) do
      get project_pull_request_analysis_path(project, analysis)
    end

    assert_match "US$0.7014", response.body
    assert_match "尚未設定美元兌新台幣匯率", response.body
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

  test "changes tab renders line-numbered add/remove/context rows, grouped by file kind, with the file's changed methods" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")
    file = analysis.changed_files.create!(
      file_path: "app/models/order.rb", change_type: "modified", additions: 1, deletions: 1,
      patch: "diff --git a/app/models/order.rb b/app/models/order.rb\n--- a/app/models/order.rb\n" \
             "+++ b/app/models/order.rb\n@@ -1,2 +1,2 @@\n class Order\n-  old_line\n+  new_line\n",
    )

    analysis.changed_code_entities.create!(
      changed_file: file, entity_type: "model", class_name: "Order", method_name: "ship!", change_kind: "modified", association_changed: true,
    )

    get project_pull_request_analysis_path(project, analysis, tab: "changes")

    assert_response :success
    assert_select "nav a.border-blue-600", text: "程式異動"
    assert_select "h3", text: /後端程式/
    assert_select "summary[id=?]", "changed-file-#{file.id}", text: /app\/models\/order.rb/
    assert_match "Order#ship!", response.body
    assert_match "關聯變更", response.body
    assert_match(%r{<td[^>]*>-  old_line</td>}, response.body)
    assert_match(%r{<td[^>]*>\+  new_line</td>}, response.body)
  end

  test "changes tab shows a binary-file message instead of attempting to parse the patch" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "diffing")
    analysis.changed_files.create!(
      file_path: "app/assets/images/logo.png", change_type: "modified",
      patch: "Binary files a/app/assets/images/logo.png and b/app/assets/images/logo.png differ\n", binary: true,
    )

    get project_pull_request_analysis_path(project, analysis, tab: "changes")

    assert_response :success
    assert_match "二進位檔案，無法顯示差異。", response.body
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
