require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "index renders imported projects in a table with a status badge" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    get root_path

    assert_response :success
    assert_select "table" do
      assert_select "td", text: project.github_full_name
    end
    assert_select "span", text: project.status_text
  end

  test "index shows an empty state when there are no projects" do
    Project.destroy_all

    get root_path

    assert_response :success
    assert_select "table", count: 0
    assert_select "p", text: "尚未匯入任何專案。"
  end

  test "the import form's labels point at their inputs" do
    get root_path

    %w[project_owner project_repository_name project_default_branch].each do |id|
      assert_select "label[for=?]", id
      assert_select "input##{id}"
    end
  end
end
