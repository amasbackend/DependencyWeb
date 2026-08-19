module Projects
  class Import < Actor
    input :project
    output :project

    def call
      project.update!(status: "importing", analysis_status: "fetching_metadata")

      repository = GithubClient.build.repository(project.github_full_name)
      project.update!(default_branch: repository.default_branch)
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
