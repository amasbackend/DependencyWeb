# frozen_string_literal: true

module GithubAnalysis
  class ResetFlags < Actor
    input :company_id

    output :company
    output :message

    def call
      self.company = Company.find(company_id)
      fail!(error: "Company not found") unless company

      flag_service = FlagUpdateService.new
      flag_service.reset_all_flags(company.name)

      self.message = "所有 flag 已重置"
    rescue StandardError => e
      fail!(error: e.message)
    end
  end
end
