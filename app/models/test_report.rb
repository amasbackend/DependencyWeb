class TestReport < ApplicationRecord
  enumerize :status, in: ModelEnum.test_report_status_enum, default: :generating

  belongs_to :pull_request_analysis
  has_many :test_cases, dependent: :destroy

  validates :structured_content, presence: true
  validates :prompt_version, presence: true
end
