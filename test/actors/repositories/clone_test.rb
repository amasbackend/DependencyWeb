require "test_helper"

class Repositories::CloneTest < ActiveSupport::TestCase
  test "clones a bare repo, records repository_path and base_sha" do
    with_scratch_repository_root do |root|
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")

      result = Repositories::Clone.result(project: project, source_url: fixture_dir)

      assert result.success?
      project.reload
      assert_equal "AMASTek/PrjJieZhou/repository.git", project.repository_path
      assert_match(/\A[0-9a-f]{40}\z/, project.base_sha)
      assert root.join("AMASTek", "PrjJieZhou", "repository.git", "HEAD").exist?
    end
  end

  test "fetches instead of re-cloning when the bare repo already exists" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")

      first = Repositories::Clone.result(project: project, source_url: fixture_dir)
      assert first.success?
      first_sha = project.reload.base_sha

      Dir.chdir(fixture_dir) do
        File.write("README.md", "updated")
        system("git", "commit", "-aqm", "second commit", exception: true)
      end

      second = Repositories::Clone.result(project: project, source_url: fixture_dir)
      assert second.success?
      project.reload
      assert_not_equal first_sha, project.base_sha
    end
  end

  test "marks the project failed with a readable message when the source is unreachable" do
    with_scratch_repository_root do
      project = Project.create!(owner: "AMASTek", repository_name: "NoSuchRepo", default_branch: "main")

      result = Repositories::Clone.result(project: project, source_url: "/no/such/path/on/disk")

      assert_not result.success?
      project.reload
      assert_equal "failed", project.status
      assert_match(/Repository 下載失敗/, project.error_message)
    end
  end
end
