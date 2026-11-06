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

  test "with no Chinese routes.rb comment, names the module from the app's own navbar menu" do
    with_scratch_repository_root do
      fixture_dir = build_fixture_rails_repo
      Dir.chdir(fixture_dir) do
        File.write("config/routes.rb", File.read("config/routes.rb").sub(/^end\s*\z/, "  resources :orders, only: [:index] # rubocop:disable Metrics/BlockLength\nend\n"))
        File.write("app/controllers/orders_controller.rb", "class OrdersController < ApplicationController\n  def index\n  end\nend\n")
        FileUtils.mkdir_p("app/views/orders")
        FileUtils.mkdir_p("app/views/layouts")
        File.write("app/views/orders/index.html.erb", "<h3>訂單</h3>\n")
        File.write("app/views/layouts/_navbar.html.erb", %(<%= link_to "訂單查詢", orders_path %>\n))
        system("git", "add", "-A", exception: true)
        system("git", "commit", "-q", "-m", "orders", exception: true)
      end
      project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", default_branch: "main")
      assert Repositories::Clone.result(project: project, source_url: fixture_dir).success?
      assert Projects::IndexCode.result(project: project).success?

      assert Projects::BuildBusinessModules.result(project: project).success?

      mod = project.business_modules.find_by(slug: "orderscontroller")
      assert_equal "訂單", mod.name
      assert_equal "locale_derived", mod.source
    end
  end
end
