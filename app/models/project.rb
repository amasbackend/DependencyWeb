class Project < ApplicationRecord
  # Requires at least one alphanumeric character so values like "." or ".."
  # can't pass — Phase 3 joins owner/repository_name directly into filesystem
  # paths (storage/repositories/<owner>/<repo>/...), so a pure-dot value would
  # be a path-traversal vector otherwise. See docs/architecture_plan.md §16.
  OWNER_FORMAT = /\A(?=.*[A-Za-z0-9])[A-Za-z0-9_.\-]+\z/

  enumerize :status, in: ModelEnum.project_status_enum, default: :pending
  enumerize :analysis_status, in: ModelEnum.project_analysis_status_enum, default: :queued

  has_many :business_modules, dependent: :destroy
  has_many :business_features, dependent: :destroy
  has_many :code_entities, dependent: :destroy
  has_many :pull_request_analyses, dependent: :destroy

  validates :owner, presence: true, format: { with: OWNER_FORMAT }
  validates :repository_name, presence: true, format: { with: OWNER_FORMAT }
  validates :github_full_name, presence: true, uniqueness: true

  before_validation :set_github_full_name

  private

  def set_github_full_name
    self.github_full_name = "#{owner}/#{repository_name}" if owner.present? && repository_name.present?
  end
end
