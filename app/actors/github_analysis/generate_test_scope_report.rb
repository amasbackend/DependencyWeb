# frozen_string_literal: true

module GithubAnalysis
  class GenerateTestScopeReport < Actor
    input :company_id
    input :pr_number
    input :format, default: "qa"
    input :pr_summary, default: nil

    output :company
    output :report
    output :markdown

    def call
      self.company = Company.find_by(id: company_id)
      fail!(error: "Company not found") unless company
      fail!(error: "PR number 不能為空") if pr_number.blank?

      summary = pr_summary.presence || fetch_pr_summary(company, pr_number)
      service = TestScopeReportService.new
      self.report = service.generate(
        company: company,
        pr_number: pr_number.to_i,
        format: format,
        pr_summary: summary,
      )
      self.markdown = service.to_markdown(report) if format.to_s == "qa" || (report.is_a?(Hash) && report[:view] == "qa")
    rescue StandardError => e
      fail!(error: e.message)
    end

    private

    def fetch_pr_summary(company, pr_number)
      owner = company.github_owner.presence || "AMASTek"
      repo = company.name
      pr_check = GithubAnalysisService.new.check_pr_exists(owner, repo, pr_number)
      return nil unless pr_check[:exists]

      pr_data = JSON.parse(pr_check[:body])
      {
        title: pr_data["title"],
        body: pr_data["body"],
        html_url: pr_data["html_url"],
        commented: pr_data["body"],
      }
    rescue StandardError
      nil
    end
  end
end
