require "test_helper"

class Repositories::FetchTest < ActiveSupport::TestCase
  test "fetches new commits from origin into the bare repo" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_git_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?

      Dir.chdir(fixture_dir) do
        File.write("README.md", "updated")
        system("git", "commit", "-aqm", "second commit", exception: true)
      end

      result = Repositories::Fetch.result(project: project)

      assert result.success?
      bare_repo = Rails.application.config.x.repository_root
      log = GitCommand.run(
        "log", "--oneline", "main",
        git_dir: File.join(bare_repo, "AMASTek", "PrjJieZhou", "repository.git")
      )
      assert_match(/second commit/, log)
    end
  end

  test "fails with a readable message when the bare repo has no such remote" do
    with_scratch_repository_root do
      project = Project.create!(owner: "AMASTek", repository_name: "Ghost", default_branch: "main")

      result = Repositories::Clone.result(project: project, source_url: build_fixture_git_repo)
      assert result.success?

      # Corrupt the remote so fetch genuinely fails, without touching real GitHub.
      GitCommand.run(
        "remote", "set-url", "origin", "/no/such/path",
        git_dir: File.join(Rails.application.config.x.repository_root, "AMASTek", "Ghost", "repository.git")
      )

      failure = Repositories::Fetch.result(project: project)

      assert_not failure.success?
    end
  end
end
