require "test_helper"
require "ostruct"

class PullRequests::FetchTest < ActiveSupport::TestCase
  def fake_pr
    OpenStruct.new(
      title: "修正 A5 未入包裝累加", body: "詳見議題文件", user: OpenStruct.new(login: "hawking"),
      base: OpenStruct.new(ref: "master", sha: "base-sha-123"),
      head: OpenStruct.new(ref: "fix/a5-stock", sha: "head-sha-456"),
    )
  end

  test "populates PR metadata and merge_base_sha on success" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "master")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)

    fake_client = Minitest::Mock.new
    fake_client.expect(:pull_request, fake_pr, [ "AMASTek/PrjJieZhou", 65 ])
    fake_client.expect(:compare, OpenStruct.new(merge_base_commit: OpenStruct.new(sha: "merge-base-789")),
      [ "AMASTek/PrjJieZhou", "base-sha-123", "head-sha-456" ])

    result = GithubClient.stub :build, fake_client do
      PullRequests::Fetch.result(pull_request_analysis: pull_request_analysis)
    end

    assert result.success?
    fake_client.verify
    pull_request_analysis.reload
    assert_equal "修正 A5 未入包裝累加", pull_request_analysis.pr_title
    assert_equal "hawking", pull_request_analysis.pr_author
    assert_equal "master", pull_request_analysis.base_branch
    assert_equal "fix/a5-stock", pull_request_analysis.head_branch
    assert_equal "merge-base-789", pull_request_analysis.merge_base_sha
  end

  test "does not fail the whole fetch when only merge_base resolution fails" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "master")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65)

    pr = fake_pr # captured as a local: inside define_singleton_method's block, `self` is
    # fake_client, not this test instance, so calling the `fake_pr` *method* there would fail
    fake_client = Object.new
    fake_client.define_singleton_method(:pull_request) { |*| pr }
    fake_client.define_singleton_method(:compare) { |*| raise StandardError, "compare unavailable" }

    result = GithubClient.stub :build, fake_client do
      PullRequests::Fetch.result(pull_request_analysis: pull_request_analysis)
    end

    assert result.success?
    assert_nil pull_request_analysis.reload.merge_base_sha
    assert_equal "master", pull_request_analysis.base_branch
  end

  test "marks the analysis failed with a readable message when the PR does not exist" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "master")
    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 999)

    fake_client = Object.new
    fake_client.define_singleton_method(:pull_request) { |*| raise Octokit::NotFound }

    result = GithubClient.stub :build, fake_client do
      PullRequests::Fetch.result(pull_request_analysis: pull_request_analysis)
    end

    assert_not result.success?
    pull_request_analysis.reload
    assert_equal "failed", pull_request_analysis.status
    assert_equal "fetching_pr", pull_request_analysis.error_stage
    assert_equal "PR #999 不存在", pull_request_analysis.error_message
  end
end
