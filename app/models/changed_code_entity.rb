class ChangedCodeEntity < ApplicationRecord
  enumerize :entity_type, in: ModelEnum.code_entity_type_enum
  enumerize :change_kind, in: ModelEnum.changed_code_entity_change_kind_enum

  belongs_to :pull_request_analysis
  belongs_to :changed_file
  belongs_to :code_entity, optional: true
  has_many :impact_items, foreign_key: :source_changed_code_entity_id, dependent: :nullify, inverse_of: :source_changed_code_entity
end
