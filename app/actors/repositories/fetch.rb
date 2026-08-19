module Repositories
  class Fetch < Actor
    include RepositoryPaths

    input :project
    output :project

    def call
      GitCommand.run("fetch", "origin", git_dir: bare_repo_path, env: fetch_env)
    rescue StandardError => e
      fail!(error: e.message)
    end

    private

    # Only real GitHub remotes need the auth header injected — inspecting the
    # actual configured remote (rather than threading a flag through from the
    # caller) keeps this actor self-contained and correct regardless of who
    # calls it.
    def fetch_env
      remote_url = GitCommand.run("remote", "get-url", "origin", git_dir: bare_repo_path).strip
      remote_url.start_with?("https://github.com") ? GitCommand.auth_env : {}
    end
  end
end
