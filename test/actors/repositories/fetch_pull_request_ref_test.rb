require "test_helper"

class Repositories::FetchPullRequestRefTest < ActiveSupport::TestCase
  test "fetches a ref that was added to the origin after the initial clone" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      # Simulate a PR opened after the project was first cloned: a new
      # commit on a branch, exposed only via refs/pull/<n>/head (GitHub's
      # convention — never advertised by a plain fetch, must be requested
      # explicitly by exact ref path).
      pr_sha = nil
      Dir.chdir(fixture_dir) do
        system("git", "checkout", "-q", "-b", "pr-branch", exception: true)
        File.write("README.md", "pr change")
        system("git", "commit", "-aqm", "pr commit", exception: true)
        pr_sha = `git rev-parse HEAD`.strip
        system("git", "update-ref", "refs/pull/65/head", pr_sha, exception: true)
      end

      result = Repositories::FetchPullRequestRef.result(project: project, pr_number: 65)

      assert result.success?
      bare_repo = File.join(Rails.application.config.x.repository_root, "AMASTek", "PrjJieZhou", "repository.git")
      assert_equal pr_sha, GitCommand.run("rev-parse", "FETCH_HEAD", git_dir: bare_repo).strip
    end
  end
end
