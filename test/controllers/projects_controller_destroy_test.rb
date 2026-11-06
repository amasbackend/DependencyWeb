require "test_helper"

class ProjectsControllerDestroyTest < ActionDispatch::IntegrationTest
  test "destroy removes the project and its cloned repository directory" do
    with_scratch_repository_root do |root|
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
      repo_dir = root.join("AMASTek", "PrjJieZhou")
      FileUtils.mkdir_p(repo_dir)

      delete project_path(project)

      assert_redirected_to root_path
      assert_not Project.exists?(project.id)
      assert_not repo_dir.exist?
    end
  end

  test "destroy succeeds even when there is no repository directory to clean up" do
    with_scratch_repository_root do
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "pending")

      delete project_path(project)

      assert_redirected_to root_path
      assert_not Project.exists?(project.id)
    end
  end
end
