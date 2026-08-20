require "test_helper"
require "ostruct"

class Projects::ImportTest < ActiveSupport::TestCase
  test "sets default_branch and keeps status importing on success" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    fake_repo = OpenStruct.new(default_branch: "main")
    fake_client = Minitest::Mock.new
    fake_client.expect(:repository, fake_repo, [ "AMASTek/PrjJieZhou" ])

    result = GithubClient.stub :build, fake_client do
      Projects::Import.result(project: project)
    end

    assert result.success?
    fake_client.verify
    project.reload
    assert_equal "importing", project.status
    assert_equal "fetching_metadata", project.analysis_status
    assert_equal "main", project.default_branch
  end

  test "§54 Advanced Option: an already-set default_branch is never overwritten by GitHub's reported default" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "release3.1.3")
    # The repository is still fetched (existence/auth is worth checking
    # early either way), but its default_branch must not clobber the
    # operator's explicit override.
    fake_repo = OpenStruct.new(default_branch: "main")
    fake_client = Minitest::Mock.new
    fake_client.expect(:repository, fake_repo, [ "AMASTek/PrjJieZhou" ])

    result = GithubClient.stub :build, fake_client do
      Projects::Import.result(project: project)
    end

    assert result.success?
    fake_client.verify
    project.reload
    assert_equal "release3.1.3", project.default_branch
  end

  test "marks project failed with a human-readable message when repository is not found" do
    project = Project.create!(owner: "AMASTek", repository_name: "Nonexistent")
    fake_client = Object.new
    def fake_client.repository(*)
      raise Octokit::NotFound
    end

    result = GithubClient.stub :build, fake_client do
      Projects::Import.result(project: project)
    end

    assert_not result.success?
    project.reload
    assert_equal "failed", project.status
    assert_equal "GitHub Repository 找不到", project.error_message
  end

  test "marks project failed with a human-readable message when token is unauthorized" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    fake_client = Object.new
    def fake_client.repository(*)
      raise Octokit::Unauthorized
    end

    result = GithubClient.stub :build, fake_client do
      Projects::Import.result(project: project)
    end

    assert_not result.success?
    project.reload
    assert_equal "failed", project.status
    assert_equal "GitHub Token 權限不足", project.error_message
  end
end
