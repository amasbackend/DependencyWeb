require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  # What the background job actually does is exercised by ProjectImportJobTest
  # and each actor's own tests — here we only care that the HTTP request
  # correctly creates the project and enqueues it, so stub the job itself
  # rather than every actor it happens to chain.
  test "create imports a new project and redirects with a success notice" do
    enqueued = false

    ProjectImportJob.stub :perform_later, ->(**) { enqueued = true } do
      post projects_path, params: { project: { owner: "AMASTek", repository_name: "PrjJieZhou" } }
    end

    assert_redirected_to root_path
    assert_not_nil flash[:notice]
    assert Project.exists?(owner: "AMASTek", repository_name: "PrjJieZhou")
    assert enqueued
  end

  test "create with an invalid owner redirects with an alert and creates no project" do
    post projects_path, params: { project: { owner: "bad owner!", repository_name: "PrjJieZhou" } }

    assert_redirected_to root_path
    assert_not_nil flash[:alert]
    assert_not Project.exists?(repository_name: "PrjJieZhou")
  end
end
