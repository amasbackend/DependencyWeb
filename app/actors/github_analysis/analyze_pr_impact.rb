# frozen_string_literal: true

module GithubAnalysis
  class AnalyzePrImpact < Actor
    input :pr_number
    input :company_id

    output :company
    output :repo
    output :impact_summary
    output :message

    def call
      self.company = Company.find_by(id: company_id)
      fail!(error: "Company not found") unless company

      fail!(error: "PR number 不能為空") if pr_number.blank?

      self.repo = company.name
      github_owner = company.github_owner.presence || "AMASTek"

      flag_service = FlagUpdateService.new
      self.impact_summary = flag_service.update_flags_from_pr(
        github_owner,
        repo,
        pr_number,
        company.name,
      )

      self.message = build_message(impact_summary)
    rescue StandardError => e
      fail!(error: e.message)
    end

    private

    def build_message(summary)
      parts = [
        "GitHub PR 分析完成",
        "Action 標記 #{summary[:action_pages_flagged]} 個",
        "Model 標記 #{summary[:relate_models_flagged]} 個",
      ]
      caller_count = summary.dig(:by_level, "caller").to_i + summary.dig(:by_level, "caller_l2").to_i
      parts << "含牽連影響 #{caller_count} 項" if caller_count.positive?
      parts.join(" · ")
    end
  end
end
