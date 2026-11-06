require "test_helper"

class OperatorPathResolverTest < ActiveSupport::TestCase
  def build_feature(module_source:, feature_source:, link_entity: true)
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou#{rand(1_000_000)}", status: "ready")
    business_module = project.business_modules.create!(name: "客戶", slug: "customers", source: module_source)
    feature = business_module.business_features.create!(
      project: project, name: "客戶列表", slug: "index", domain_action: "index", source: feature_source,
    )

    if link_entity
      entity = project.code_entities.create!(
        entity_type: "controller", name: "CustomersController#index",
        class_name: "CustomersController", method_name: "index",
        file_path: "app/controllers/customers_controller.rb", signature_hash: "sig-#{rand(1_000_000)}",
      )
      FeatureCodeEntity.create!(business_feature: feature, code_entity: entity, role: "controller_action")
    end

    feature
  end

  test "a route-comment-derived module and feature resolve to the strongest tier and no manual review" do
    feature = build_feature(module_source: "locale_derived", feature_source: "locale_derived")

    path = OperatorPathResolver.call(feature: feature)

    assert_equal "route_comment_derived", path.confidence_source
    assert_not path.needs_manual_review
    assert_equal [ "客戶", "客戶列表" ], path.segments.map(&:label)
    assert_equal [ "route_comment_derived", "route_comment_derived" ], path.segments.map(&:evidence_kind)
  end

  test "a CRUD-convention feature resolves to the crud_convention_derived tier and no manual review" do
    feature = build_feature(module_source: "route_derived", feature_source: "route_derived")

    path = OperatorPathResolver.call(feature: feature)

    assert_equal "crud_convention_derived", path.confidence_source
    assert_not path.needs_manual_review
    assert_equal "controller_action_only", path.segments.first.evidence_kind
    assert_equal "crud_convention_derived", path.segments.second.evidence_kind
  end

  test "an LLM-inferred feature with no other evidence requires manual review" do
    feature = build_feature(module_source: "route_derived", feature_source: "llm_inferred")

    path = OperatorPathResolver.call(feature: feature)

    assert_equal "controller_action_only", path.confidence_source
    assert path.needs_manual_review
  end

  test "the feature segment links the anchor controller-action code entity when one exists" do
    feature = build_feature(module_source: "locale_derived", feature_source: "locale_derived")

    path = OperatorPathResolver.call(feature: feature)

    assert_equal feature.code_entities.first, path.segments.second.code_entity
    assert_nil path.segments.first.code_entity
  end

  test "the feature segment has no code entity when nothing is linked yet" do
    feature = build_feature(module_source: "locale_derived", feature_source: "locale_derived", link_entity: false)

    path = OperatorPathResolver.call(feature: feature)

    assert_nil path.segments.second.code_entity
  end

  test "resolving twice replaces the previous path instead of duplicating it" do
    feature = build_feature(module_source: "locale_derived", feature_source: "locale_derived")

    OperatorPathResolver.call(feature: feature)
    OperatorPathResolver.call(feature: feature)

    assert_equal 1, OperatorPath.where(business_feature: feature).count
    assert_equal 2, OperatorPathSegment.where(operator_path: feature.operator_path).count
  end
end
