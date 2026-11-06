class OperatorPathSegment < ApplicationRecord
  enumerize :evidence_kind, in: ModelEnum.operator_path_source_enum, default: :controller_action_only

  belongs_to :operator_path
  belongs_to :code_entity, optional: true

  validates :label, presence: true
  validates :position, presence: true, uniqueness: { scope: :operator_path_id }
end
