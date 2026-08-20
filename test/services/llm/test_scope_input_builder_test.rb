require "test_helper"

class Llm::TestScopeInputBuilderTest < ActiveSupport::TestCase
  test "builds a deterministic input hash and a ref map back to real impact_item ids" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    code_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-1",
    )
    pull_request_analysis = project.pull_request_analyses.create!(
      pr_number: 65, pr_title: "出貨修正", pr_description: "修正出貨數量", pr_author: "alice",
      base_branch: "main", head_branch: "fix/ship",
    )
    changed_file = pull_request_analysis.changed_files.create!(
      file_path: "app/actors/orders/ship.rb", change_type: "modified", additions: 3, deletions: 1,
      patch: "@@ -1,3 +1,3 @@\n-old\n+new\n",
    )
    pull_request_analysis.changed_code_entities.create!(
      changed_file: changed_file, code_entity: code_entity, entity_type: "actor",
      class_name: "Orders::Ship", method_name: "call", change_kind: "modified",
    )
    impact_item = pull_request_analysis.impact_items.create!(
      code_entity: code_entity, business_feature: feature, impact_level: "direct_change",
      reason: "此 PR 直接修改：Orders::Ship#call", evidence: { changed_file: "app/actors/orders/ship.rb" },
    )

    result = Llm::TestScopeInputBuilder.call(pull_request_analysis)

    assert_equal({ owner: "AMASTek", repository_name: "PrjJieZhou" }, result.input[:project])
    assert_equal(65, result.input[:pull_request][:pr_number])
    assert_equal(1, result.input[:changed_files].size)
    assert_equal(1, result.input[:changed_code_entities].size)

    impact_entry = result.input[:impact_items].first
    assert_equal "IMPACT-1", impact_entry[:ref]
    assert_equal "direct_change", impact_entry[:impact_level]
    assert_equal "Orders::Ship#call", impact_entry[:code_entity]
    assert_equal "出貨", impact_entry[:business_feature]

    assert_equal({ "IMPACT-1" => impact_item.id }, result.ref_to_impact_item_id)
    assert_equal [ { module: "訂單", feature: "出貨" } ], result.input[:known_features]
  end

  test "truncates a long patch to keep LLM cost bounded" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    pull_request_analysis.changed_files.create!(
      file_path: "app/models/big.rb", change_type: "modified", additions: 1, deletions: 0,
      patch: "x" * 5000,
    )

    result = Llm::TestScopeInputBuilder.call(pull_request_analysis)

    excerpt = result.input[:changed_files].first[:patch_excerpt]
    assert excerpt.bytesize <= Llm::TestScopeInputBuilder::PATCH_EXCERPT_LIMIT
  end
end
