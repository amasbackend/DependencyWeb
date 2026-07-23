# frozen_string_literal: true

module CodeAnalysis
  class SyncFromGithub < Actor
    input :company_id
    input :branch, default: nil

    output :company
    output :message
    output :statistics

    play :load_company,
         :sync_code

    private

    def load_company
      self.company = Company.find_by(id: company_id)
      fail!(error: "找不到指定的專案") unless company
    end

    def sync_code
      owner = company.github_owner.presence || "AMASTek"
      sync_branch = branch.presence || company.github_branch.presence || "master"

      result = CodeAnalysis::RelationsFromGithub.result(
        project_name: company.name,
        owner: owner,
        repo: company.name,
        branch: sync_branch,
        existing_company: company,
      )

      fail!(error: result.error) unless result.success?

      self.company = result.company
      self.statistics = result.statistics
      self.message = "已從 #{owner}/#{company.name} (#{sync_branch}) 同步母資料"
    end
  end
end
