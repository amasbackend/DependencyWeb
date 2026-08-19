class ImpactItem < ApplicationRecord
  enumerize :impact_level, in: ModelEnum.impact_item_level_enum

  belongs_to :pull_request_analysis
  belongs_to :business_feature, optional: true
  belongs_to :code_entity, optional: true
  belongs_to :source_changed_code_entity, class_name: "ChangedCodeEntity", optional: true, inverse_of: :impact_items
  has_many :test_cases, dependent: :nullify
end
