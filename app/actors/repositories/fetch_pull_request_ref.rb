module Repositories
  # Makes a PR's head commit locally available without needing a worktree —
  # `git diff` (unlike Graphify, Phase 10) operates on the object database
  # directly. GitHub always honors an explicit fetch of the well-known
  # `refs/pull/<n>/head` ref even though it isn't advertised by a plain
  # `git fetch`/`ls-remote` — verified against the real target repo.
  class FetchPullRequestRef < Actor
    include RepositoryPaths

    input :project
    input :pr_number

    def call
      GitCommand.run("fetch", "origin", "refs/pull/#{pr_number}/head", git_dir: bare_repo_path, env: GitCommand.auth_env)
    rescue StandardError => e
      fail!(error: e.message)
    end
  end
end
