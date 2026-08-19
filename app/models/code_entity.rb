class CodeEntity < ApplicationRecord
  enumerize :entity_type, in: ModelEnum.code_entity_type_enum

  belongs_to :project
  has_many :feature_code_entities, dependent: :destroy
  has_many :business_features, through: :feature_code_entities
  has_many :changed_code_entities, dependent: :nullify
  has_many :impact_items, dependent: :nullify

  validates :name, presence: true
  validates :file_path, presence: true
  validates :signature_hash, presence: true, uniqueness: { scope: :project_id }
end
