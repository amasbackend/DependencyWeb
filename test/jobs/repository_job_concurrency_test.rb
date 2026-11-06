require "test_helper"

class RepositoryJobConcurrencyTest < ActiveSupport::TestCase
  test "an import and a PR analysis of the same project share one concurrency key" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    analysis = project.pull_request_analyses.create!(pr_number: 65)

    import_key = ProjectImportJob.new(project_id: project.id).concurrency_key
    analysis_key = PullRequestAnalysisJob.new(pull_request_analysis_id: analysis.id).concurrency_key

    assert_equal "ProjectRepository/#{project.id}", import_key
    assert_equal import_key, analysis_key
    assert_equal 1, ProjectImportJob.concurrency_limit
    assert_equal 1, PullRequestAnalysisJob.concurrency_limit
  end

  test "different projects don't block each other" do
    a = Project.create!(owner: "AMASTek", repository_name: "A")
    b = Project.create!(owner: "AMASTek", repository_name: "B")

    assert_not_equal ProjectImportJob.new(project_id: a.id).concurrency_key, ProjectImportJob.new(project_id: b.id).concurrency_key
  end
end
