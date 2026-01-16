# frozen_string_literal: true

module CodeAnalysis
  class ImportFromGithub < Actor
    input :owner
    input :repo
    input :branch, default: "main"

    output :project_name
    output :company
    output :message
    output :statistics

    play :analyze_code

    private

    def analyze_code
      self.project_name = repo

      result = CodeAnalysis::RelationsFromGithub.result(
        project_name: project_name,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      fail!(error: result.error) unless result.success?

      self.company = result.company
      self.statistics = result.statistics
      self.message = "成功匯入 #{owner}/#{repo} (分支: #{branch})"
    end
  end
end
