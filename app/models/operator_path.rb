class OperatorPath < ApplicationRecord
  enumerize :confidence_source, in: ModelEnum.operator_path_source_enum, default: :controller_action_only

  belongs_to :business_feature
  has_many :segments, -> { order(:position) }, class_name: "OperatorPathSegment", dependent: :destroy
end
