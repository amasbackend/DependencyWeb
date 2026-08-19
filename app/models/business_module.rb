class BusinessModule < ApplicationRecord
  enumerize :source, in: ModelEnum.business_entity_source_enum, default: :manual

  belongs_to :project
  has_many :business_features, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :project_id }
end
