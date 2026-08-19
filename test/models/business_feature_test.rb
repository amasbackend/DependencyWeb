require "test_helper"

class BusinessFeatureTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    @business_module = @project.business_modules.create!(name: "使用者", slug: "user")
  end

  test "rejects duplicate slug within the same business module" do
    @business_module.business_features.create!(project: @project, name: "使用者列表", slug: "index")
    duplicate = @business_module.business_features.new(project: @project, name: "重複", slug: "index")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "已經被使用"
  end

  test "allows the same slug across different business modules" do
    other_module = @project.business_modules.create!(name: "客戶", slug: "customer")
    @business_module.business_features.create!(project: @project, name: "使用者列表", slug: "index")
    feature = other_module.business_features.new(project: @project, name: "客戶列表", slug: "index")

    assert feature.valid?
  end

  test "maps to code entities through feature_code_entities" do
    feature = @business_module.business_features.create!(project: @project, name: "使用者列表", slug: "index")
    entity = @project.code_entities.create!(
      entity_type: "controller", name: "UsersController",
      file_path: "app/controllers/users_controller.rb", signature_hash: "sig-1"
    )
    FeatureCodeEntity.create!(business_feature: feature, code_entity: entity, role: "controller_action")

    assert_equal [ entity ], feature.code_entities
  end
end
