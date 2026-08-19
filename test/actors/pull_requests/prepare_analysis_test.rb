require "test_helper"

class PullRequests::PrepareAnalysisTest < ActiveJob::TestCase
  test "creates a new analysis and enqueues the fetch job" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    assert_enqueued_with(job: PullRequestAnalysisJob) do
      result = PullRequests::PrepareAnalysis.result(project: project, pr_number: 65)
      assert result.success?
      assert_equal 65, result.pull_request_analysis.pr_number
      assert_equal "queued", result.pull_request_analysis.status
    end
  end

  test "reuses an existing non-terminal analysis for the same PR number instead of duplicating it" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    existing = project.pull_request_analyses.create!(pr_number: 65, status: "fetching_pr")

    result = PullRequests::PrepareAnalysis.result(project: project, pr_number: 65)

    assert_equal existing.id, result.pull_request_analysis.id
    assert_equal 1, project.pull_request_analyses.where(pr_number: 65).count
  end

  test "starts a fresh analysis when the previous one for the same PR number already finished" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    project.pull_request_analyses.create!(pr_number: 65, status: "completed")

    result = PullRequests::PrepareAnalysis.result(project: project, pr_number: 65)

    assert_not_equal "completed", result.pull_request_analysis.status
    assert_equal 2, project.pull_request_analyses.where(pr_number: 65).count
  end
end
