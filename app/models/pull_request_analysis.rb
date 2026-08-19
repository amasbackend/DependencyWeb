class PullRequestAnalysis < ApplicationRecord
  # llm_failed counts as terminal here even though it's specifically
  # recoverable (§63 — earlier stages already succeeded, only the LLM step
  # needs redoing) — re-triggering "分析 PR" for one should start a fresh
  # attempt; a more targeted "regenerate report only" action is Phase 12+
  # scope, not built yet.
  TERMINAL_STATUSES = %w[completed failed llm_failed].freeze

  enumerize :status, in: ModelEnum.pull_request_analysis_status_enum, default: :queued

  belongs_to :project
  has_many :changed_files, dependent: :destroy
  has_many :changed_code_entities, dependent: :destroy
  has_many :graphify_artifacts, dependent: :destroy
  has_many :impact_items, dependent: :destroy
  has_many :test_reports, dependent: :destroy

  validates :pr_number, presence: true, numericality: { only_integer: true }
end
