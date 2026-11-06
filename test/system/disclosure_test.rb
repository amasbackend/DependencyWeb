require "application_system_test_case"

# Covers the Stimulus disclosure_controller.js interaction shared by the
# homepage project table (Phase 2) and the business feature technical-view
# table (Phase 3) — the two places a row's detail panel is toggled via JS
# rather than a native <details> element, so it needs a real browser to
# verify (unlike most of this app's server-rendered content).
class DisclosureTest < ApplicationSystemTestCase
  test "expanding a project row on the homepage reveals its detail panel" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")

    visit root_path

    detail = find("tr[data-disclosure-target='content']", visible: :all)
    assert_not detail.visible?

    find("button[aria-label='展開專案詳細資訊']").click

    assert detail.visible?
    within(detail) { assert_text "PrjJieZhou" }
  end

  test "expanding a business feature row in technical view reveals its linked entities" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    business_module = project.business_modules.create!(name: "客戶", slug: "customers")
    feature = business_module.business_features.create!(project: project, name: "客戶列表", slug: "index")
    entity = project.code_entities.create!(
      entity_type: "controller", name: "CustomersController#index",
      class_name: "CustomersController", method_name: "index",
      file_path: "app/controllers/customers_controller.rb", signature_hash: "sig-1",
    )
    FeatureCodeEntity.create!(business_feature: feature, code_entity: entity, role: "controller_action")

    visit project_path(project, view: "technical")

    detail = find("tr[data-disclosure-target='content']", visible: :all)
    assert_not detail.visible?

    find("button[aria-label='展開技術實體']").click

    assert detail.visible?
    within(detail) { assert_text "CustomersController#index" }
  end
end
