class BusinessFeature < ApplicationRecord
  enumerize :source, in: ModelEnum.business_entity_source_enum, default: :manual

  belongs_to :project
  belongs_to :business_module
  has_many :feature_code_entities, dependent: :destroy
  has_many :code_entities, through: :feature_code_entities
  has_many :impact_items, dependent: :nullify
  has_many :test_cases, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :business_module_id }
end
