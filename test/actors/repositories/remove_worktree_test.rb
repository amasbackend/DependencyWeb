require "test_helper"

class Repositories::RemoveWorktreeTest < ActiveSupport::TestCase
  test "removes a materialized working tree" do
    with_scratch_repository_root do |root|
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      assert Repositories::CreateWorktree.result(project: project, name: "pr-65", ref: project.reload.base_sha).success?
      worktree_dir = root.join("AMASTek", "PrjJieZhou", "worktrees", "pr-65")
      assert worktree_dir.exist?

      result = Repositories::RemoveWorktree.result(project: project, name: "pr-65")

      assert result.success?
      assert_not worktree_dir.exist?
    end
  end

  test "is idempotent when the worktree was already removed" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      result = Repositories::RemoveWorktree.result(project: project, name: "never-created")

      assert result.success?
    end
  end
end
