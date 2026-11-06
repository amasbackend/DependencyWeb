# Resolves how an operator navigates to reach one BusinessFeature, as a
# 2-segment path: 業務模組 -> 業務功能. Deliberately reuses the evidence the
# app already computed while NAMING the module/feature (BusinessModule#source
# / BusinessFeature#source, set by Projects::BuildBusinessModules /
# BusinessFeatureNamer) rather than re-deriving anything — a route-line
# comment or CRUD-convention name is exactly the same evidence an operator
# path segment needs, so recomputing it here would just duplicate
# RoutesFileParser/BusinessFeatureNamer under a different name.
#
# frontend_redesign_plan.md §7's full 5-tier evidence list (adding i18n
# controller/action keys and view button/link text as extra sources) needs
# new scanners this app doesn't have yet — ModelEnum.operator_path_source_enum
# already reserves slots for them (i18n_derived/view_text_derived) so adding
# those tiers later is a resolver change, not another migration.
class OperatorPathResolver
  # BusinessModule#source has no llm_inferred tier (Projects::BuildBusinessModules
  # only ever sets locale_derived or route_derived) — its "route_derived" means
  # "no resources-line comment, humanized controller name" instead, which is
  # weaker evidence than a feature's "route_derived" (an actual CRUD template).
  MODULE_SOURCE_MAPPING = {
    "locale_derived" => "route_comment_derived",
    "route_derived" => "controller_action_only",
  }.freeze

  FEATURE_SOURCE_MAPPING = {
    "locale_derived" => "route_comment_derived",
    "route_derived" => "crud_convention_derived",
    "llm_inferred" => "controller_action_only",
  }.freeze

  def self.call(feature:)
    new(feature).call
  end

  def initialize(feature)
    @feature = feature
  end

  def call
    OperatorPath.transaction do
      path = OperatorPath.find_or_initialize_by(business_feature: feature)
      path.confidence_source = feature_evidence_kind
      path.needs_manual_review = feature_evidence_kind == "controller_action_only"
      path.resolved_at = Time.current
      path.save!

      path.segments.destroy_all
      path.segments.create!(position: 0, label: business_module.name, evidence_kind: module_evidence_kind)
      path.segments.create!(
        position: 1, label: feature.name, evidence_kind: feature_evidence_kind, code_entity: anchor_code_entity,
      )

      path
    end
  end

  private

  attr_reader :feature

  def business_module
    feature.business_module
  end

  def module_evidence_kind
    MODULE_SOURCE_MAPPING.fetch(business_module.source.to_s, "controller_action_only")
  end

  def feature_evidence_kind
    FEATURE_SOURCE_MAPPING.fetch(feature.source.to_s, "controller_action_only")
  end

  # The controller action the feature's name was actually derived from — the
  # only FeatureCodeEntity role Projects::BuildBusinessFeatures ever links
  # (see docs/architecture_plan.md's confirmed-scope notes), so this is
  # already the single reliable anchor rather than one of several roles.
  def anchor_code_entity
    feature.feature_code_entities.find { |fce| fce.role == "controller_action" }&.code_entity
  end
end
