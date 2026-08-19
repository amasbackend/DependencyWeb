require "test_helper"

class BusinessFeatureNamerTest < ActiveSupport::TestCase
  def route(action, comment: nil, standard: false)
    RoutesFileParser::Route.new(controller: "Setting::CustomersController", action: action, comment: comment, standard: standard)
  end

  test "a route-line comment always wins, regardless of action name" do
    result = BusinessFeatureNamer.call(route: route("start", comment: "開始加工"), resource_label: "工單")

    assert_equal "開始加工", result.name
    assert_equal "start", result.slug
    assert_equal "locale_derived", result.source
    assert_not result.needs_llm
  end

  test "index and show use their own templates" do
    assert_equal "客戶列表", BusinessFeatureNamer.call(route: route("index"), resource_label: "客戶").name
    assert_equal "客戶詳細資料", BusinessFeatureNamer.call(route: route("show"), resource_label: "客戶").name
  end

  test "new and create collapse into one 新增 feature with the same slug" do
    new_result = BusinessFeatureNamer.call(route: route("new"), resource_label: "客戶")
    create_result = BusinessFeatureNamer.call(route: route("create"), resource_label: "客戶")

    assert_equal "新增客戶", new_result.name
    assert_equal "新增客戶", create_result.name
    assert_equal new_result.slug, create_result.slug
  end

  test "edit and update collapse into one 編輯 feature with the same slug" do
    edit_result = BusinessFeatureNamer.call(route: route("edit"), resource_label: "客戶")
    update_result = BusinessFeatureNamer.call(route: route("update"), resource_label: "客戶")

    assert_equal "編輯客戶", edit_result.name
    assert_equal "編輯客戶", update_result.name
    assert_equal edit_result.slug, update_result.slug
  end

  test "destroy uses its own template" do
    assert_equal "刪除客戶", BusinessFeatureNamer.call(route: route("destroy"), resource_label: "客戶").name
  end

  test "a custom action with no comment needs LLM inference rather than a guess" do
    result = BusinessFeatureNamer.call(route: route("cooling"), resource_label: "工單")

    assert result.needs_llm
    assert_nil result.name
    assert_equal "llm_inferred", result.source
  end
end
