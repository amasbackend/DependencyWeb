class ChangedFile < ApplicationRecord
  enumerize :change_type, in: ModelEnum.changed_file_change_type_enum

  belongs_to :pull_request_analysis
  has_many :changed_code_entities, dependent: :destroy

  validates :file_path, presence: true, uniqueness: { scope: :pull_request_analysis_id }
end
