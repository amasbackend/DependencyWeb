require "test_helper"

class Llm::TestScopeInputBuilderTest < ActiveSupport::TestCase
  setup do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou#{rand(1_000_000)}", status: "ready")
    @analysis = project.pull_request_analyses.create!(pr_number: 65, pr_title: "訂單調整", status: "mapping_features")
  end

  def change_entity(file_path, class_name, method_name = nil, patch: nil)
    file = @analysis.changed_files.find_or_create_by!(file_path: file_path) { |f| f.change_type = "modified"; f.patch = patch }
    cce = @analysis.changed_code_entities.create!(
      changed_file: file, entity_type: "actor", class_name: class_name, method_name: method_name, change_kind: "modified",
    )
    @analysis.impact_items.create!(source_changed_code_entity: cce, impact_level: "direct_change", reason: "直接修改")
    cce
  end

  def build
    Llm::TestScopeInputBuilder.call(@analysis, snapshot: screen_fixture_snapshot)
  end

  test "puts a change on the batch for the screens it was traced to, with those screens' real labels" do
    change_entity("app/actors/orders/validate.rb", "Orders::Validate", "check_qty")

    chunk = build.chunks.find { |c| c.key == "orders" }

    assert_equal [ "orders#new" ], chunk.screen_keys
    assert_equal [ "CHG-1" ], chunk.refs
    screen = chunk.input[:screens].first
    assert_equal "訂單管理 › 新增訂單", screen[:name]
    assert_includes screen[:labels], "送出"
    assert_equal [ "orders#new" ], chunk.input[:changes].first[:screens]
    assert_equal({ "order" => { name: "訂單", attributes: { "qty" => "數量" } } }, chunk.input[:glossary])
  end

  test "sends changes that reach no screen to a separate batch with the whole screen directory" do
    change_entity("app/actors/machines/report.rb", "Machines::Report")

    other = build.chunks.find { |c| c.key == "other-1" }

    assert_equal [ "CHG-1" ], other.refs
    assert_equal "外部系統 API（非畫面操作）", other.input[:changes].first[:category]
    assert_equal %w[orders#index orders#new], other.input[:screens].map { |s| s[:screen_key] }.sort
  end

  test "settles unreferenced and dev-only changes deterministically, without the LLM" do
    change_entity("app/actors/orphan.rb", "Orphan")
    @analysis.changed_files.create!(file_path: ".prettierrc", change_type: "modified")

    result = build

    assert_empty result.chunks
    assert_equal [ [ "CHG-1" ], [ "FILE-1" ] ], result.deterministic_items.map { |i| i["refs"] }
  end

  test "every ref is either in some batch or settled deterministically — nothing is dropped" do
    change_entity("app/actors/orders/validate.rb", "Orders::Validate", "check_qty")
    change_entity("app/actors/machines/report.rb", "Machines::Report")
    change_entity("app/actors/orphan.rb", "Orphan")
    @analysis.changed_files.create!(file_path: "db/migrate/20260101000000_add_qty_to_orders.rb", change_type: "added")

    result = build
    accounted = result.chunks.flat_map(&:refs) + result.deterministic_items.flat_map { |i| i["refs"] }

    assert_equal result.ref_index.keys.sort, accounted.uniq.sort
  end

  test "ref_index links a changed class's ref to its direct_change impact item" do
    cce = change_entity("app/actors/orders/validate.rb", "Orders::Validate", "check_qty")

    assert_equal @analysis.impact_items.find_by(source_changed_code_entity: cce).id, build.ref_index["CHG-1"][:impact_item_id]
  end

  test "narrows a changed method's diff to the hunks that touch it" do
    patch = <<~DIFF
      @@ -1,3 +1,3 @@ class Orders::Validate < Actor
       def call
      -  old_call
      +  new_call
      @@ -6,2 +6,2 @@ def check_qty
      -  qty > 0
      +  qty >= 0
    DIFF
    change_entity("app/actors/orders/validate.rb", "Orders::Validate", "check_qty", patch: patch)

    diff = build.chunks.first.input[:diffs].first[:diff]

    assert_match "qty >= 0", diff
    assert_no_match(/new_call/, diff)
  end
end
