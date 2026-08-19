require "test_helper"

class ProjectsControllerShowTest < ActionDispatch::IntegrationTest
  setup do
    @project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    @module = @project.business_modules.create!(name: "客戶", slug: "customers")
    @feature = @module.business_features.create!(project: @project, name: "客戶列表", slug: "index")
    @entity = @project.code_entities.create!(
      entity_type: "controller", name: "CustomersController#index",
      class_name: "CustomersController", method_name: "index",
      file_path: "app/controllers/customers_controller.rb", signature_hash: "sig-1",
    )
    FeatureCodeEntity.create!(business_feature: @feature, code_entity: @entity, role: "controller_action")
  end

  test "show renders the business module/feature tree by default" do
    get project_path(@project)

    assert_response :success
    assert_match "客戶", response.body
    assert_match "客戶列表", response.body
    assert_no_match "CustomersController#index", response.body
  end

  test "technical view additionally shows the linked code entity" do
    get project_path(@project, view: "technical")

    assert_response :success
    assert_match "CustomersController#index", response.body
  end

  test "search filters the feature tree and lists matching code entities" do
    get project_path(@project, q: "客戶")

    assert_response :success
    assert_match "客戶列表", response.body
  end

  test "search with no matches shows an empty state instead of the full tree" do
    get project_path(@project, q: "no-such-thing-xyz")

    assert_response :success
    assert_no_match "客戶列表", response.body
  end
end
