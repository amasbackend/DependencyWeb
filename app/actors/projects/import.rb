module Projects
  class Import < Actor
    input :project
    output :project

    def call
      project.update!(status: "importing", analysis_status: "fetching_metadata")

      # Still fetched even when default_branch is already set (§54's
      # Advanced Option override) — repo existence/auth is worth checking
      # early regardless; only the *branch* assignment is conditional, so
      # the operator's explicit override is never silently clobbered by
      # whatever GitHub reports.
      repository = GithubClient.build.repository(project.github_full_name)
      project.update!(default_branch: repository.default_branch) if project.default_branch.blank?
    rescue Octokit::NotFound
      fail_with(I18n.t("actor.projects.import.repository_not_found"))
    rescue Octokit::Unauthorized, Octokit::Forbidden
      fail_with(I18n.t("actor.projects.import.unauthorized"))
    rescue StandardError => e
      fail_with(e.message)
    end

    private

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[ProjectImport:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
