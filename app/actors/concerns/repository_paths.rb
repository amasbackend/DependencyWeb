# Shared path construction for Repositories::* actors, matching the layout
# mandated by project_plan.md §5-6:
#
#   REPOSITORY_ROOT/<owner>/<repo>/repository.git   (bare repo)
#   REPOSITORY_ROOT/<owner>/<repo>/worktrees/<name>/ (one per analysis)
#
# Centralized here (rather than duplicated per actor) so path-safety logic
# — and the REPOSITORY_ROOT join point — has exactly one place to get right.
# Requires the including actor to have a `project` accessor (owner/
# repository_name are validated at the model level — see Project::OWNER_FORMAT
# — so joining them directly into a Pathname is safe from traversal).
module RepositoryPaths
  extend ActiveSupport::Concern

  def repository_root
    Pathname.new(Rails.application.config.x.repository_root || REPOSITORY_ROOT)
  end

  def project_root_path
    repository_root.join(project.owner, project.repository_name)
  end

  def bare_repo_path
    project_root_path.join("repository.git")
  end

  def relative_repo_path
    bare_repo_path.relative_path_from(repository_root).to_s
  end

  def worktree_dir_for(name)
    project_root_path.join("worktrees", name)
  end
end
