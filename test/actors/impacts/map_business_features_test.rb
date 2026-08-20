require "test_helper"

class Impacts::MapBusinessFeaturesTest < ActiveSupport::TestCase
  def build_project
    Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
  end

  test "resolves a code entity linked to exactly one feature by updating the row in place" do
    project = build_project
    code_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-1",
    )
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    FeatureCodeEntity.create!(business_feature: feature, code_entity: code_entity, role: "actor")

    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    item = pull_request_analysis.impact_items.create!(code_entity: code_entity, impact_level: "direct_dependency")

    result = Impacts::MapBusinessFeatures.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    assert_equal 1, pull_request_analysis.impact_items.count
    item.reload
    assert_equal feature.id, item.business_feature_id
    assert_not item.needs_manual_review
  end

  test "duplicates the row per feature when a code entity backs more than one feature" do
    project = build_project
    code_entity = project.code_entities.create!(
      entity_type: "model", name: "Order", class_name: "Order",
      file_path: "app/models/order.rb", signature_hash: "sig-2",
    )
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    ship_feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")
    refund_feature = business_module.business_features.create!(project: project, name: "退款", slug: "refund", domain_action: "refund")
    FeatureCodeEntity.create!(business_feature: ship_feature, code_entity: code_entity, role: "model")
    FeatureCodeEntity.create!(business_feature: refund_feature, code_entity: code_entity, role: "model")

    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    pull_request_analysis.impact_items.create!(
      code_entity: code_entity, impact_level: "regression_candidate", reason: "shared model", evidence: { shared_model: "Order" },
    )

    result = Impacts::MapBusinessFeatures.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    items = pull_request_analysis.impact_items.reload
    assert_equal 2, items.count
    assert_equal [ ship_feature.id, refund_feature.id ].sort, items.map(&:business_feature_id).sort
    # The duplicate keeps the same evidence — it's the same underlying code
    # change, just relevant to more than one feature.
    assert items.all? { |i| i.reason == "shared model" }
    assert items.all? { |i| i.evidence == { "shared_model" => "Order" } }
  end

  test "flags needs_manual_review when a code entity backs no feature at all" do
    project = build_project
    code_entity = project.code_entities.create!(
      entity_type: "service", name: "OrphanService", class_name: "OrphanService",
      file_path: "app/services/orphan_service.rb", signature_hash: "sig-3",
    )
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    item = pull_request_analysis.impact_items.create!(code_entity: code_entity, impact_level: "indirect_dependency")

    result = Impacts::MapBusinessFeatures.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    item.reload
    assert_nil item.business_feature_id
    assert item.needs_manual_review
  end

  test "flags needs_manual_review when the impact item never resolved to a code entity" do
    project = build_project
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)
    item = pull_request_analysis.impact_items.create!(code_entity_id: nil, impact_level: "direct_change")

    result = Impacts::MapBusinessFeatures.result(pull_request_analysis: pull_request_analysis)

    assert result.success?
    item.reload
    assert_nil item.business_feature_id
    assert item.needs_manual_review
  end
end
