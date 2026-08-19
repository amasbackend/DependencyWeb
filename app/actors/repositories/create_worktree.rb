module Repositories
  class CreateWorktree < Actor
    include RepositoryPaths

    input :project
    input :name # e.g. "pr-65" — becomes the worktree's directory name
    input :ref  # sha or branch to check out into the new worktree
    output :worktree_path

    def call
      dir = worktree_dir_for(name)

      if dir.exist?
        fail!(error: I18n.t("actor.repositories.create_worktree.already_exists", name: name))
        return
      end

      FileUtils.mkdir_p(dir.dirname)
      GitCommand.run("worktree", "add", dir.to_s, ref, git_dir: bare_repo_path)

      self.worktree_path = dir.relative_path_from(repository_root).to_s
    rescue StandardError => e
      fail!(error: e.message)
    end
  end
end
