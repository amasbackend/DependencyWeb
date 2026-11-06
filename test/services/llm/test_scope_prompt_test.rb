require "test_helper"

class Llm::TestScopePromptTest < ActiveSupport::TestCase
  test "SKILL_VERSION is loaded from skill.md's frontmatter" do
    assert_equal "v2", Llm::TestScopePrompt::SKILL_VERSION
  end

  test "the batch prompt carries the screen labels and change refs it must stay within" do
    input = {
      pull_request: { number: 65, title: "訂單調整", description: "" },
      screens: [ { screen_key: "orders#new", name: "訂單管理 › 新增訂單", url: "/orders/new", labels: [ "送出" ] } ],
      changes: [ { ref: "CHG-1", subject: "Orders::Validate#check_qty" } ],
      diffs: [], glossary: {},
    }

    result = Llm::TestScopePrompt.build(input)

    assert_equal Llm::TestScopePrompt::SYSTEM_PROMPT, result[:system]
    assert_match "orders#new", result[:user]
    assert_match "送出", result[:user]
    assert_match "CHG-1", result[:user]
  end

  test "the summary prompt uses the separate summary skill" do
    result = Llm::TestScopePrompt.build_summary({ batches: [] })

    assert_equal Llm::TestScopePrompt::SUMMARY_PROMPT, result[:system]
  end

  test "repair_note lists the exact validation problems" do
    note = Llm::TestScopePrompt.repair_note([ "test_cases[0].screen_key \"x\" is not one of this batch's screens" ])

    assert_match "請修正", note
    assert_match "test_cases[0].screen_key", note
  end

  # output_schema.json is the human-reviewable doc of the merged report shape;
  # these keep it from drifting away from what TestScopeSchema enforces.
  test "output_schema.json's required test_case fields match what TestScopeSchema actually enforces" do
    schema = JSON.parse(File.read(Rails.root.join("skills", "test_scope", "output_schema.json")))
    documented_required = schema.dig("$defs", "testCase", "required")

    valid_test_case = {
      "name" => "x", "verification_purpose" => "x", "expected_result" => "x",
      "steps" => [ "x" ], "evidence" => [ "x" ], "impact_item_refs" => [ "CHG-1" ], "case_type" => "core_change",
    }
    base_payload = {
      "summary" => { "title" => "x" }, "affected_modules" => [], "regression_cases" => [],
      "pass_criteria" => [], "manual_checks" => [], "uncertain_items" => [],
    }

    assert_empty Llm::TestScopeSchema.validate(base_payload.merge("test_cases" => [ valid_test_case ])),
      "sanity check: the fully-populated fixture should itself be valid"

    documented_required.each do |field|
      errors = Llm::TestScopeSchema.validate(base_payload.merge("test_cases" => [ valid_test_case.except(field) ]))

      assert errors.any? { |e| e.include?(field) },
        "output_schema.json documents `#{field}` as required, but omitting it produced no validation error: #{errors.inspect}"
    end
  end

  test "output_schema.json's case_type enum matches TestScopeSchema::CASE_TYPES" do
    schema = JSON.parse(File.read(Rails.root.join("skills", "test_scope", "output_schema.json")))

    assert_equal Llm::TestScopeSchema::CASE_TYPES, schema.dig("$defs", "testCase", "properties", "case_type", "enum")
  end
end
