class FeatureCodeEntity < ApplicationRecord
  enumerize :role, in: ModelEnum.feature_code_entity_role_enum
  enumerize :source, in: ModelEnum.feature_code_entity_source_enum, default: :manual

  belongs_to :business_feature
  belongs_to :code_entity

  validates :code_entity_id, uniqueness: { scope: :business_feature_id }
end
