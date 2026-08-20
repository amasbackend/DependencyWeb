require "test_helper"

class Llm::AnalyzeTestScopeTest < ActiveSupport::TestCase
  def build_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    code_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-1",
    )
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    changed_file = pull_request_analysis.changed_files.create!(
      file_path: "app/actors/orders/ship.rb", change_type: "modified", additions: 3, deletions: 1,
    )
    pull_request_analysis.changed_code_entities.create!(
      changed_file: changed_file, code_entity: code_entity, entity_type: "actor",
      class_name: "Orders::Ship", method_name: "call", change_kind: "modified",
    )
    pull_request_analysis.impact_items.create!(
      code_entity: code_entity, business_feature: feature, impact_level: "direct_change",
      reason: "此 PR 直接修改：Orders::Ship#call", evidence: { changed_file: "app/actors/orders/ship.rb" },
    )

    pull_request_analysis
  end

  def stub_provider(response)
    fake_provider = Object.new
    fake_provider.define_singleton_method(:generate) { |**| response }
    fake_provider
  end

  test "persists a completed test report and test cases from a well-formed LLM response" do
    pra = build_scenario
    payload = {
      "summary" => { "title" => "修正出貨數量", "changes" => [ { "type" => "bugfix", "description" => "修正出貨計算" } ] },
      "affected_modules" => [ "訂單" ],
      "test_cases" => [
        {
          "name" => "出貨儲存驗證", "feature" => "出貨", "case_type" => "core_change",
          "impact_item_refs" => [ "IMPACT-1" ], "page_path" => "/orders/:id/ship",
          "verification_purpose" => "確認出貨可正常儲存", "steps" => [ "填寫出貨數量", "按儲存" ],
          "expected_result" => "儲存成功", "failure_criteria" => "顯示錯誤", "notes" => nil,
          "evidence" => [ "IMPACT-1", "app/actors/orders/ship.rb" ],
        },
      ],
      "regression_cases" => [],
      "pass_criteria" => [ "儲存成功" ],
      "manual_checks" => [],
      "uncertain_items" => [],
    }
    response = Llm::Response.new(content: payload.to_json, provider: "gemini", model: "gemini-2.5-flash", input_tokens: 100, output_tokens: 50)

    result = nil
    Llm::Provider.stub :current, stub_provider(response) do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert result.success?
    pra.reload
    assert_equal "llm_analyzing", pra.status

    report = result.test_report
    assert_equal "completed", report.status
    assert_equal "gemini", report.llm_provider
    assert_equal "v1", report.prompt_version
    assert_equal 100, report.input_tokens

    assert_equal 1, report.test_cases.count
    test_case = report.test_cases.first
    assert_equal "core_change", test_case.case_type
    assert_equal "出貨", test_case.business_feature.name
    assert_equal pra.impact_items.first.id, test_case.impact_item_id
    assert_equal 1, test_case.position
  end

  test "merges regression_cases in as case_type regression" do
    pra = build_scenario
    payload = {
      "summary" => { "title" => "x", "changes" => [] },
      "affected_modules" => [],
      "test_cases" => [],
      "regression_cases" => [
        {
          "name" => "回歸案例", "feature" => nil, "impact_item_refs" => [ "IMPACT-1" ],
          "page_path" => nil, "verification_purpose" => "確認沒壞", "steps" => [ "查看" ],
          "expected_result" => "正常", "failure_criteria" => nil, "notes" => nil, "evidence" => [ "IMPACT-1" ],
        },
      ],
      "pass_criteria" => [], "manual_checks" => [], "uncertain_items" => [],
    }
    response = Llm::Response.new(content: payload.to_json, provider: "gemini", model: "gemini-2.5-flash")

    result = nil
    Llm::Provider.stub :current, stub_provider(response) do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert result.success?
    assert_equal "regression", result.test_report.test_cases.first.case_type
  end

  test "fails with llm_failed and does not create a report when the response fails schema validation" do
    pra = build_scenario
    response = Llm::Response.new(content: '{"summary":{}}', provider: "gemini", model: "gemini-2.5-flash")

    result = nil
    Llm::Provider.stub :current, stub_provider(response) do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert_not result.success?
    pra.reload
    assert_equal "llm_failed", pra.status
    assert_equal "llm_analyzing", pra.error_stage
    assert_empty pra.test_reports
  end

  test "fails with llm_failed when the provider itself errors" do
    pra = build_scenario
    failing_provider = Object.new
    def failing_provider.generate(**)
      raise Llm::Provider::Error, "no API key configured"
    end

    result = nil
    Llm::Provider.stub :current, failing_provider do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert_not result.success?
    pra.reload
    assert_equal "llm_failed", pra.status
    assert_match "no API key configured", pra.error_message
  end

  # §70: LLM 回傳非法 JSON — must fail cleanly (llm_failed), never propagate
  # a raw JSON::ParserError out of the actor (this runs inside a background
  # job, but §68's "never let the app 500" intent still applies — an
  # uncaught parse error would surface as a failed/retried job with a raw
  # stack trace instead of the same human-readable llm_failed state every
  # other LLM failure produces).
  test "fails with llm_failed, not a raw JSON parse error, when the response isn't valid JSON" do
    pra = build_scenario
    response = Llm::Response.new(content: "這不是 JSON，只是一段文字回覆。", provider: "gemini", model: "gemini-2.5-flash")

    result = nil
    Llm::Provider.stub :current, stub_provider(response) do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert_not result.success?
    pra.reload
    assert_equal "llm_failed", pra.status
    assert_equal "llm_analyzing", pra.error_stage
    assert_empty pra.test_reports
  end

  # §70: LLM timeout — a network-level timeout from the provider's HTTP
  # client must be caught the same way as any other provider error, not
  # bubble up as a raw Faraday exception.
  test "fails with llm_failed, not a raw timeout exception, when the provider times out" do
    pra = build_scenario
    timing_out_provider = Object.new
    def timing_out_provider.generate(**)
      raise Faraday::TimeoutError, "execution expired"
    end

    result = nil
    Llm::Provider.stub :current, timing_out_provider do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert_not result.success?
    pra.reload
    assert_equal "llm_failed", pra.status
    assert_match "execution expired", pra.error_message
    assert_empty pra.test_reports
  end

  test "keeps a test case with an unknown feature name rather than discarding it" do
    pra = build_scenario
    payload = {
      "summary" => { "title" => "x", "changes" => [] },
      "affected_modules" => [],
      "test_cases" => [
        {
          "name" => "案例", "feature" => "不存在的功能", "case_type" => "core_change",
          "impact_item_refs" => [ "IMPACT-1" ], "page_path" => nil,
          "verification_purpose" => "x", "steps" => [ "x" ], "expected_result" => "x",
          "failure_criteria" => nil, "notes" => nil, "evidence" => [ "IMPACT-1" ],
        },
      ],
      "regression_cases" => [], "pass_criteria" => [], "manual_checks" => [], "uncertain_items" => [],
    }
    response = Llm::Response.new(content: payload.to_json, provider: "gemini", model: "gemini-2.5-flash")

    result = nil
    Llm::Provider.stub :current, stub_provider(response) do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: pra)
    end

    assert result.success?
    assert_nil result.test_report.test_cases.first.business_feature_id
  end
end
