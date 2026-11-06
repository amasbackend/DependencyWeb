require "test_helper"

class Llm::TestScopeSchemaTest < ActiveSupport::TestCase
  def valid_case(overrides = {})
    {
      "name" => "A3 冷卻儲存",
      "feature" => "A3 冷卻",
      "case_type" => "core_change",
      "impact_item_refs" => [ "IMPACT-1" ],
      "page_path" => "/workstation/a3_order/:work_date",
      "verification_purpose" => "確認冷卻儲存成功",
      "steps" => [ "填寫冷卻資料", "按儲存" ],
      "expected_result" => "儲存成功",
      "failure_criteria" => "出現錯誤訊息",
      "notes" => nil,
      "evidence" => [ "IMPACT-1", "app/actors/a3/cool.rb" ],
    }.merge(overrides)
  end

  def valid_payload(overrides = {})
    {
      "summary" => { "title" => "修正 A3 冷卻", "changes" => [ { "type" => "bugfix", "description" => "修正累加" } ] },
      "affected_modules" => [ "A3 冷卻" ],
      "test_cases" => [ valid_case ],
      "regression_cases" => [ valid_case.except("case_type") ],
      "pass_criteria" => [ "儲存成功" ],
      "manual_checks" => [ "確認庫存數字" ],
      "uncertain_items" => [ { "description" => "某個變更", "reason" => "證據不足", "evidence" => [] } ],
    }.merge(overrides)
  end

  test "a well-formed response has no errors" do
    assert_empty Llm::TestScopeSchema.validate(valid_payload)
  end

  test "rejects a non-object response" do
    assert_equal [ "response is not a JSON object" ], Llm::TestScopeSchema.validate([ 1, 2 ])
  end

  test "requires summary.title" do
    errors = Llm::TestScopeSchema.validate(valid_payload("summary" => { "changes" => [] }))
    assert_includes errors, "summary.title is missing"
  end

  test "requires case_type on test_cases but not regression_cases" do
    payload = valid_payload("test_cases" => [ valid_case.except("case_type") ])
    errors = Llm::TestScopeSchema.validate(payload)

    assert(errors.any? { |e| e.include?("test_cases[0].case_type") })
  end

  test "rejects a test case with no impact_item_refs — every case must cite real evidence" do
    payload = valid_payload("test_cases" => [ valid_case("impact_item_refs" => []) ])
    errors = Llm::TestScopeSchema.validate(payload)

    assert_includes errors, "test_cases[0].impact_item_refs must be a non-empty array"
  end

  test "rejects a test case with empty evidence" do
    payload = valid_payload("test_cases" => [ valid_case("evidence" => []) ])
    errors = Llm::TestScopeSchema.validate(payload)

    assert_includes errors, "test_cases[0].evidence must be a non-empty array"
  end

  test "rejects an uncertain_item with no description" do
    payload = valid_payload("uncertain_items" => [ { "reason" => "x" } ])
    errors = Llm::TestScopeSchema.validate(payload)

    assert_includes errors, "uncertain_items[0].description is missing"
  end

  test "preparation is optional — omitting it entirely is valid" do
    assert_empty Llm::TestScopeSchema.validate(valid_payload)
  end

  test "rejects a preparation that isn't an array when present" do
    errors = Llm::TestScopeSchema.validate(valid_payload("preparation" => "not an array"))
    assert_includes errors, "preparation must be an array"
  end

  def chunk_case(overrides = {})
    {
      "name" => "數量為 0 可送出", "screen_key" => "orders#new", "case_type" => "core_change",
      "impact_item_refs" => [ "CHG-1" ], "verification_purpose" => "x", "steps" => [ "點選「送出」" ], "expected_result" => "成功",
    }.merge(overrides)
  end

  def validate_chunk(test_case)
    Llm::TestScopeSchema.validate_chunk({ "test_cases" => [ test_case ], "uncertain_items" => [] }, screen_keys: [ "orders#new" ], refs: [ "CHG-1", "FILE-1" ])
  end

  test "a batch answer on the batch's own screen citing its own refs is valid, regression included" do
    assert_empty validate_chunk(chunk_case)
    assert_empty validate_chunk(chunk_case("case_type" => "regression"))
  end

  test "rejects a batch case placed on a screen outside the batch" do
    assert_includes validate_chunk(chunk_case("screen_key" => "made/up#page")),
      "test_cases[0].screen_key \"made/up#page\" is not one of this batch's screens"
  end

  test "rejects a batch case citing a ref the batch doesn't own" do
    assert_includes validate_chunk(chunk_case("impact_item_refs" => [ "CHG-9" ])), "test_cases[0].impact_item_refs cites unknown refs CHG-9"
  end
end
