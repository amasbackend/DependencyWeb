module Repositories
  class Clone < Actor
    include RepositoryPaths

    input :project
    # Overridable only for tests, so the real git CLI can be exercised
    # against a local fixture repo without ever reaching GitHub. Production
    # callers omit this and get the real GitHub URL.
    input :source_url, default: nil, allow_nil: true
    output :project

    def call
      project.update!(analysis_status: "cloning")

      if bare_repo_path.exist?
        Repositories::Fetch.call(project: project)
      else
        FileUtils.mkdir_p(project_root_path)
        # --mirror (not plain --bare) sets remote.origin.fetch to +refs/*:refs/*,
        # so a later plain `git fetch origin` updates refs/heads/<branch> directly
        # in place — a plain --bare clone leaves local branches stale on fetch,
        # since it configures no refspec to update them at all.
        GitCommand.run("clone", "--mirror", clone_url, bare_repo_path.to_s, env: clone_env)
      end

      sha = GitCommand.run("rev-parse", project.default_branch, git_dir: bare_repo_path).strip
      project.update!(repository_path: relative_repo_path, base_sha: sha)
    rescue StandardError => e
      fail_with(I18n.t("actor.repositories.clone.failed", message: e.message))
    end

    private

    def clone_url
      source_url || "https://github.com/#{project.owner}/#{project.repository_name}.git"
    end

    # Only inject the GitHub auth header for real GitHub clones — a
    # source_url override (test fixtures only) needs no credentials, and
    # calling GithubConfig.access_token without a token configured would
    # raise even for a purely local clone.
    def clone_env
      source_url ? {} : GitCommand.auth_env
    end

    def fail_with(message)
      project.update!(status: "failed", error_message: message)
      Rails.logger.error("[RepositoryClone:#{project.id}] #{message}")
      fail!(error: message)
    end
  end
end
