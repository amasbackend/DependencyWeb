# frozen_string_literal: true

class PrAnalysis < ApplicationRecord
  belongs_to :company

  validates :pr_number, presence: true

  scope :for_pr, ->(company_id, pr_number) { where(company_id: company_id, pr_number: pr_number) }

  def self.save_snapshot!(company:, pr_number:, impact_summary:, analysis_input:, qa_report:, tech_report:)
    record = find_or_initialize_by(company: company, pr_number: pr_number)
    record.assign_attributes(
      impact_summary: impact_summary,
      analysis_input: analysis_input,
      qa_report: qa_report,
      tech_report: tech_report,
      analyzed_at: Time.current,
    )
    record.save!
    record
  end
end
