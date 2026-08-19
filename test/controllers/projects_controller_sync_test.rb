require "test_helper"

class ProjectsControllerSyncTest < ActionDispatch::IntegrationTest
  test "sync marks the project syncing and redirects with a success notice" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    ProjectImportJob.stub :perform_later, ->(**) { true } do
      post sync_project_path(project)
    end

    assert_redirected_to project_path(project)
    assert_not_nil flash[:notice]
    assert_equal "syncing", project.reload.status
  end
end
