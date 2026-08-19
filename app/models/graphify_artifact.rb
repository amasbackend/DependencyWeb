class GraphifyArtifact < ApplicationRecord
  belongs_to :pull_request_analysis

  validates :format, presence: true
end
