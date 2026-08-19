require "test_helper"

class Projects::BuildBusinessModulesTest < ActiveSupport::TestCase
  test "creates a business module named from the resources-line comment, with 管理 suffix stripped" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      assert Projects::IndexCode.result(project: project).success?

      result = Projects::BuildBusinessModules.result(project: project)

      assert result.success?
      mod = project.business_modules.find_by(slug: "userscontroller")
      assert mod
      assert_equal "使用者", mod.name
      assert_equal "locale_derived", mod.source
      assert result.parsed_routes.any? { |r| r.controller == "UsersController" }
    end
  end

  test "re-running replaces stale modules rather than duplicating them" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      assert Projects::IndexCode.result(project: project).success?

      assert Projects::BuildBusinessModules.result(project: project).success?
      first_count = project.business_modules.count

      assert Projects::BuildBusinessModules.result(project: project).success?

      assert_equal first_count, project.business_modules.count
    end
  end
end
