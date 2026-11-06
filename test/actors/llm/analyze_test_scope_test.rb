require "test_helper"

class Llm::AnalyzeTestScopeTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou#{rand(1_000_000)}", status: "ready")
    business_module = @project.business_modules.create!(name: "訂單", slug: "orders")
    @feature = business_module.business_features.create!(project: @project, name: "新增訂單", slug: "new", domain_action: "new")
    action_entity = @project.code_entities.create!(
      entity_type: "controller", name: "OrdersController#new", class_name: "OrdersController", method_name: "new",
      file_path: "app/controllers/orders_controller.rb", signature_hash: "sig-new",
    )
    @feature.feature_code_entities.create!(code_entity: action_entity, role: "controller_action")

    @analysis = @project.pull_request_analyses.create!(pr_number: 65, pr_title: "訂單數量檢查", status: "mapping_features")
    @screen_change = change_entity("app/actors/orders/validate.rb", "Orders::Validate", "check_qty") # → orders#new
    change_entity("app/actors/machines/report.rb", "Machines::Report") # → api, "other" batch
  end

  def change_entity(file_path, class_name, method_name = nil)
    file = @analysis.changed_files.create!(file_path: file_path, change_type: "modified")
    cce = @analysis.changed_code_entities.create!(
      changed_file: file, entity_type: "actor", class_name: class_name, method_name: method_name, change_kind: "modified",
    )
    @analysis.impact_items.create!(source_changed_code_entity: cce, impact_level: "direct_change", reason: "直接修改")
    cce
  end

  def response(payload, input_tokens: 100)
    Llm::Response.new(content: payload.is_a?(String) ? payload : payload.to_json, provider: "openai", model: "gpt-4.1",
                      input_tokens: input_tokens, output_tokens: 10)
  end

  def summary_payload
    {
      "summary" => { "title" => "訂單數量檢查調整", "changes" => [ { "type" => "錯誤修正", "description" => "數量為 0 時可以送出" } ] },
      "affected_modules" => [ "訂單管理" ], "pass_criteria" => [ "所有案例通過" ], "manual_checks" => [ "確認機台回報" ],
    }
  end

  # Answers each batch from its own prompt: one case on the batch's first
  # screen citing its first ref, the rest of its refs explained as uncertain.
  def batch_payload(prompt)
    screen_keys = prompt.scan(/"screen_key": "([^"]+)"/).flatten
    refs = prompt.scan(/"ref": "((?:CHG|FILE)-\d+)"/).flatten.uniq
    {
      "chunk_summary" => [ { "type" => "錯誤修正", "description" => "數量檢查" } ],
      "test_cases" => [
        {
          "name" => "數量為 0 的訂單可以送出", "screen_key" => screen_keys.first, "case_type" => "core_change",
          "impact_item_refs" => [ refs.first ], "verification_purpose" => "以前數量 0 會被擋，現在可以送出",
          "steps" => [ "進入「訂單管理」", "點選「新增訂單」", "「數量」填 0 後點選「送出」" ],
          "expected_result" => "儲存成功", "failure_criteria" => "出現錯誤訊息", "notes" => nil, "evidence" => [ refs.first ],
        },
      ],
      "uncertain_items" => refs.drop(1).map { |ref| { "description" => "背景計算", "reason" => "畫面看不到", "refs" => [ ref ] } },
      "preparation" => [ "可新增訂單的帳號" ], "manual_checks" => [],
    }
  end

  def fake_provider(&chunk_answer)
    chunk_answer ||= ->(prompt, _attempt) { response(batch_payload(prompt)) }
    attempts = Hash.new(0)
    test = self
    provider = Object.new
    provider.define_singleton_method(:generate) do |system:, prompt:, **|
      next test.response(summary_payload_for_fake) if system == Llm::TestScopePrompt::SUMMARY_PROMPT

      key = prompt[/"screen_key": "([^"]+)"/, 1]
      attempts[key] += 1
      chunk_answer.call(prompt, attempts[key])
    end
    provider.define_singleton_method(:summary_payload_for_fake) { test.summary_payload }
    provider
  end

  def run_analysis(provider = fake_provider)
    result = nil
    Llm::Provider.stub :current, provider do
      result = Llm::AnalyzeTestScope.result(pull_request_analysis: @analysis, snapshot: screen_fixture_snapshot)
    end
    result
  end

  test "persists one report from all batches, with screen-derived page paths and features" do
    result = run_analysis

    assert result.success?, result.error
    report = result.test_report
    assert_equal "completed", report.status
    assert_equal "訂單數量檢查調整", report.title
    assert_equal "v2", report.prompt_version
    assert_equal Llm::TestScopePrompt::SKILL_VERSION, report.skill_version
    assert_equal Llm::TestScopeSchema::VERSION, report.schema_version
    assert_match(/\A[0-9a-f]{64}\z/, report.evidence_hash)
    assert_equal 300, report.input_tokens # two batches + the summary call

    case_on_screen = report.test_cases.find_by(page_path: "訂單管理 › 新增訂單（/orders/new）")
    assert case_on_screen
    assert_equal @feature, case_on_screen.business_feature
    assert_equal @analysis.impact_items.find_by(source_changed_code_entity: @screen_change).id, case_on_screen.impact_item_id

    data = report.structured_content
    assert_equal 2, data["batches"].size
    assert_equal [ "CHG-1", "CHG-2" ], data["screen_map"].map { |m| m["ref"] }
    assert_equal [ "訂單管理 › 新增訂單（/orders/new）" ], data["screen_map"].first["screens"]
  end

  test "records token usage and the estimated cost of every call on the report" do
    report = run_analysis.test_report

    assert_equal 300, report.input_tokens
    assert_equal 30, report.output_tokens
    # 300 input × $2 + 30 output × $8, per 1M tokens (gpt-4.1)
    assert_equal BigDecimal("0.00084"), report.estimated_cost_usd
    assert_equal "gpt-4.1", report.pricing["model"]
    assert(report.structured_content["batches"].all? { |b| b["cost_usd"] })
  end

  test "leaves the cost unknown rather than guessing when the model has no price" do
    provider = fake_provider do |prompt, _attempt|
      response(batch_payload(prompt)).tap { |r| r.model = "some-unknown-model" }
    end

    assert_nil run_analysis(provider).test_report.estimated_cost_usd
  end

  test "a run that fails after calls went through keeps its usage as a failed report" do
    result = nil
    Llm::TestScopeSchema.stub :validate, [ "boom" ] do
      result = run_analysis
    end

    assert_not result.success?
    failed = @analysis.test_reports.sole
    assert_equal "failed", failed.status
    assert_equal 300, failed.input_tokens
    assert failed.estimated_cost_usd.positive?
    assert_match "boom", failed.error_message
  end

  test "asks once more, only about the refs a valid batch answer left unaddressed" do
    supplement_prompts = []
    provider = fake_provider do |prompt, _attempt|
      payload = batch_payload(prompt)
      if prompt.include?("尚未交代")
        supplement_prompts << prompt
        payload["test_cases"] = []
      else
        payload["uncertain_items"] = [] # silent on every ref but the first
      end
      response(payload)
    end

    report = run_analysis(provider).test_report

    assert_equal 0, supplement_prompts.size, "single-ref batches have nothing left to ask about"
    assert(report.structured_content["batches"].none? { |b| b["supplemented"] })

    # A batch with two refs on its screen: the first answer covers only one.
    change_entity("app/actors/orders/create.rb", "Orders::Create")
    report = run_analysis(provider).test_report

    assert_equal 1, supplement_prompts.size
    assert_match "CHG-3", supplement_prompts.first
    assert(report.structured_content["batches"].any? { |b| b["supplemented"] == 1 })
    assert_empty report.structured_content["uncertain_items"].select { |i| i["description"].include?("尚未產生測試步驟") }
  end

  test "asks a batch once more with the validation errors when its first answer is invalid" do
    prompts = []
    provider = fake_provider do |prompt, attempt|
      prompts << prompt
      payload = batch_payload(prompt)
      payload["test_cases"][0]["screen_key"] = "made/up#page" if attempt == 1
      response(payload)
    end

    result = run_analysis(provider)

    assert result.success?, result.error
    assert prompts.any? { |p| p.include?("請修正") && p.include?("is not one of this batch's screens") }
    assert(result.test_report.structured_content["batches"].any? { |b| b["repaired"] })
  end

  test "drops cases that are still invalid after the retry and lists their refs for manual review" do
    provider = fake_provider do |prompt, _attempt|
      payload = batch_payload(prompt)
      payload["test_cases"][0]["screen_key"] = "made/up#page"
      response(payload)
    end

    result = run_analysis(provider)

    assert result.success?, result.error
    report = result.test_report
    assert_equal 0, report.test_cases.count
    uncovered = report.structured_content["uncertain_items"].select { |i| i["description"].include?("尚未產生測試步驟") }
    assert_equal [ [ "CHG-1" ], [ "CHG-2" ] ], uncovered.map { |i| i["refs"] }.sort
  end

  test "an uncertain note from one batch is dropped once another batch covered that ref" do
    provider = fake_provider do |prompt, _attempt|
      payload = batch_payload(prompt)
      payload["uncertain_items"] << { "description" => "此畫面看不到", "reason" => "非本畫面", "refs" => payload["test_cases"][0]["impact_item_refs"] }
      response(payload)
    end

    result = run_analysis(provider)

    descriptions = result.test_report.structured_content["uncertain_items"].map { |i| i["description"] }
    assert_not_includes descriptions, "此畫面看不到"
  end

  test "keeps the report when one batch errors, and says which batch failed" do
    provider = fake_provider do |prompt, _attempt|
      raise Llm::Provider::Error, "OpenAI API error (500)" if prompt.include?("外部系統 API")

      response(batch_payload(prompt))
    end

    result = run_analysis(provider)

    assert result.success?, result.error
    failed = result.test_report.structured_content["uncertain_items"].find { |i| i["description"].include?("產生失敗") }
    assert_equal [ "CHG-2" ], failed["refs"]
    assert(result.test_report.structured_content["batches"].any? { |b| b["error"] })
  end

  test "fails with llm_failed when every batch errors" do
    provider = fake_provider { |_prompt, _attempt| raise Llm::Provider::Error, "no API key configured" }

    result = run_analysis(provider)

    assert_not result.success?
    @analysis.reload
    assert_equal "llm_failed", @analysis.status
    # The provider errored before returning any usage — nothing was billed.
    assert_equal "llm_analyzing", @analysis.error_stage
    assert_match "no API key configured", @analysis.error_message
    assert_empty @analysis.test_reports
  end

  test "falls back to the PR title when the summary call fails" do
    provider = fake_provider
    provider.define_singleton_method(:summary_payload_for_fake) { raise Llm::Provider::Error, "timeout" }

    result = run_analysis(provider)

    assert result.success?, result.error
    assert_equal "訂單數量檢查", result.test_report.title
  end

  test "records LlmConfig.temperature on the report when LLM_TEMPERATURE is configured" do
    with_env("LLM_TEMPERATURE" => "0.2") do
      assert_equal 0.2, run_analysis.test_report.temperature
    end
  end

  test "evidence_hash is identical across two runs over the same unchanged PR state" do
    first = run_analysis.test_report
    second = run_analysis.test_report

    assert_equal first.evidence_hash, second.evidence_hash
  end
end
