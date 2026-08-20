class ImpactItem < ApplicationRecord
  enumerize :impact_level, in: ModelEnum.impact_item_level_enum

  # §43's Business View risk tiers, derived deterministically from the
  # already-computed impact_level (Phase 11's real graph traversal) — never
  # an LLM judgment call, so "風險理由必須由實際 Dependency / Diff 支撐" holds
  # by construction rather than needing separate enforcement.
  RISK_BY_IMPACT_LEVEL = {
    "direct_change" => "high", "direct_dependency" => "high",
    "indirect_dependency" => "medium", "regression_candidate" => "low",
  }.freeze
  RISK_LABEL = { "high" => "高風險", "medium" => "中風險", "low" => "低風險" }.freeze
  RISK_ORDER = %w[high medium low].freeze

  belongs_to :pull_request_analysis
  belongs_to :business_feature, optional: true
  belongs_to :code_entity, optional: true
  belongs_to :source_changed_code_entity, class_name: "ChangedCodeEntity", optional: true, inverse_of: :impact_items
  has_many :test_cases, dependent: :nullify

  def risk_level
    RISK_BY_IMPACT_LEVEL[impact_level.to_s]
  end

  def risk_label
    RISK_LABEL[risk_level]
  end
end
