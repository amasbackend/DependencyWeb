require "test_helper"

class ProjectsControllerShowPaginationTest < ActionDispatch::IntegrationTest
  FEATURE_COUNT = 30

  setup do
    @project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    business_module = @project.business_modules.create!(name: "客戶", slug: "customers")

    FEATURE_COUNT.times do |i|
      label = format("%02d", i)
      feature = business_module.business_features.create!(project: @project, name: "功能 #{label}", slug: "feature-#{label}")
      entity = @project.code_entities.create!(
        entity_type: "controller", name: "Controller##{label}",
        class_name: "Controller#{label}", method_name: "index",
        file_path: "app/controllers/c#{label}.rb", signature_hash: "sig-#{label}",
      )
      FeatureCodeEntity.create!(business_feature: feature, code_entity: entity, role: "controller_action")
    end
  end

  test "show paginates business features at 25 per page" do
    get project_path(@project)

    assert_response :success
    assert_match "功能 00", response.body
    assert_match "第 1 / 2 頁", response.body
    assert_no_match "功能 29", response.body
  end

  test "page 2 shows the remaining features" do
    get project_path(@project, page: 2)

    assert_response :success
    assert_match "功能 29", response.body
    assert_no_match "功能 00", response.body
  end

  test "technical view with many features does not issue a query per row" do
    assert_query_count(max: 12) do
      get project_path(@project, view: "technical")
    end

    assert_response :success
    assert_match "Controller#00", response.body
  end
end
