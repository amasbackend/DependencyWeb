# frozen_string_literal: true

module GithubAnalysis
  class UpdateFlags < Actor
    input :owner
    input :pr_number
    input :company_id

    output :repo
    output :company
    output :message

    play :grep_company,
         :update_flags_from_pr

    private

    def grep_company
      self.company = Company.find(company_id)
      self.repo = company&.name

      return if company

      fail!(error: "Company not found")
    end

    def update_flags_from_pr
      fail!(error: "PR number 不能為空") if pr_number.blank?

      flag_service = FlagUpdateService.new
      flag_service.update_flags_from_pr(owner, repo, pr_number, company.name)

      self.message = "GitHub PR 分析完成！"
    rescue StandardError => e
      fail!(error: e.message)
    end
  end
end
