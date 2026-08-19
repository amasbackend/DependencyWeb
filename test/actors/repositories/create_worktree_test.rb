require "test_helper"

class Repositories::CreateWorktreeTest < ActiveSupport::TestCase
  test "materializes a working tree with real files at the given ref" do
    with_scratch_repository_root do |root|
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      result = Repositories::CreateWorktree.result(project: project, name: "pr-65", ref: project.reload.base_sha)

      assert result.success?
      assert_equal "AMASTek/PrjJieZhou/worktrees/pr-65", result.worktree_path
      assert root.join("AMASTek", "PrjJieZhou", "worktrees", "pr-65", "README.md").exist?
    end
  end

  test "fails without touching the filesystem when the worktree name is already taken" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      assert Repositories::CreateWorktree.result(project: project, name: "pr-65", ref: project.reload.base_sha).success?

      result = Repositories::CreateWorktree.result(project: project, name: "pr-65", ref: project.base_sha)

      assert_not result.success?
      assert_match(/已存在/, result.error)
    end
  end
end
