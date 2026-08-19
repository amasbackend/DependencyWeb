module Repositories
  class RemoveWorktree < Actor
    include RepositoryPaths

    input :project
    input :name # same value passed to Repositories::CreateWorktree

    def call
      dir = worktree_dir_for(name)
      return unless dir.exist? # already removed — idempotent no-op, see §51

      GitCommand.run("worktree", "remove", dir.to_s, "--force", git_dir: bare_repo_path)
    rescue StandardError => e
      fail!(error: e.message)
    end
  end
end
