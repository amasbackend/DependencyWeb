# frozen_string_literal: true

module GithubAnalysis
  class UpdateFlags < Actor
    input :pr_number
    input :company_id

    output :repo
    output :company
    output :message
    output :impact_summary

    play :analyze_pr_impact

    private

    def analyze_pr_impact
      result = GithubAnalysis::AnalyzePrImpact.result(
        pr_number: pr_number,
        company_id: company_id,
      )

      unless result.success?
        fail!(error: result.error)
        return
      end

      self.company = result.company
      self.repo = result.repo
      self.impact_summary = result.impact_summary
      self.message = result.message
    end
  end
end
