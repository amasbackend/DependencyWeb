require "test_helper"

class Projects::PullRequestAnalysesControllerTest < ActionDispatch::IntegrationTest
  test "create with a valid PR number starts an analysis and redirects to it" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    enqueued = false

    PullRequestAnalysisJob.stub :perform_later, ->(**) { enqueued = true } do
      post project_pull_request_analyses_path(project), params: { pr_number: "65" }
    end

    analysis = project.pull_request_analyses.find_by(pr_number: 65)
    assert_redirected_to project_pull_request_analysis_path(project, analysis)
    assert_not_nil flash[:notice]
    assert enqueued
  end

  test "create with a non-integer PR number redirects back with an alert and creates nothing" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    post project_pull_request_analyses_path(project), params: { pr_number: "65abc" }

    assert_redirected_to project_path(project)
    assert_not_nil flash[:alert]
    assert_not project.pull_request_analyses.exists?
  end

  test "show renders the analysis, including a base-branch mismatch warning when relevant" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "master", status: "ready")
    analysis = project.pull_request_analyses.create!(
      pr_number: 65, status: "fetching_pr", pr_title: "修正問題", base_branch: "test/i18n"
    )

    get project_pull_request_analysis_path(project, analysis)

    assert_response :success
    assert_match "修正問題", response.body
    assert_match(/Base Branch/, response.body)
  end
end
