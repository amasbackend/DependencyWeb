require "test_helper"

class ScreenImpactLocatorTest < ActiveSupport::TestCase
  setup do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou#{rand(1_000_000)}", status: "ready")
    @analysis = project.pull_request_analyses.create!(pr_number: 65, status: "mapping_features")
    @snapshot = screen_fixture_snapshot
    @catalog = ScreenCatalog.call(snapshot: @snapshot)
  end

  def change_entity(file_path, entity_type, class_name, method_name = nil)
    file = @analysis.changed_files.find_or_create_by!(file_path: file_path) { |f| f.change_type = "modified" }
    @analysis.changed_code_entities.create!(
      changed_file: file, entity_type: entity_type, class_name: class_name, method_name: method_name, change_kind: "modified",
    )
  end

  def locate
    ScreenImpactLocator.call(pull_request_analysis: @analysis, snapshot: @snapshot, catalog: @catalog).index_by(&:subject)
  end

  test "traces a changed actor up its callers to the screen that submits to the controller action" do
    change_entity("app/actors/orders/validate.rb", "actor", "Orders::Validate", "check_qty")

    mapping = locate.fetch("Orders::Validate#check_qty")

    assert_equal "CHG-1", mapping.ref
    assert_includes mapping.entry_actions, "orders#create"
    assert_equal [ "orders#new" ], mapping.screen_keys
    assert_nil mapping.bucket
    assert_equal "Orders::Validate#check_qty → Orders::Create → OrdersController#create", mapping.trace.first
  end

  test "maps a changed private controller method to the actions that call it" do
    change_entity("app/controllers/orders_controller.rb", "controller", "OrdersController", "order_params")

    assert_equal [ "orders#create" ], locate.fetch("OrdersController#order_params").entry_actions
  end

  test "buckets a change that only reaches a controller with no screen as an API" do
    change_entity("app/actors/machines/report.rb", "actor", "Machines::Report")

    mapping = locate.fetch("Machines::Report")
    assert_equal "api", mapping.bucket
    assert_empty mapping.screen_keys
  end

  test "flags a changed class nothing references" do
    change_entity("app/actors/orphan.rb", "actor", "Orphan")

    assert_equal "unreferenced", locate.fetch("Orphan").bucket
  end

  test "maps changed frontend and database files that have no parsed class" do
    @analysis.changed_files.create!(file_path: "app/packs/src/javascripts/orders/OrderForm.vue", change_type: "modified")
    @analysis.changed_files.create!(file_path: "db/migrate/20260101000000_add_qty_to_orders.rb", change_type: "added")

    mappings = locate
    vue = mappings.fetch("app/packs/src/javascripts/orders/OrderForm.vue")
    assert_equal "FILE-1", vue.ref
    assert_equal [ "orders#new" ], vue.screen_keys
    assert_equal "database", mappings.fetch("db/migrate/20260101000000_add_qty_to_orders.rb").bucket
  end

  test "a file already covered by a changed class gets no separate FILE ref" do
    change_entity("app/actors/orders/validate.rb", "actor", "Orders::Validate", "check_qty")

    assert_equal [ "CHG-1" ], locate.values.map(&:ref)
  end

  test "traces a template only a background job renders back to the screen that triggers the job" do
    @snapshot = screen_fixture_snapshot(
      "app/jobs/print_order_tag_job.rb" => "class PrintOrderTagJob < ApplicationJob\n  def perform\n    render_to_string(template: \"orders/tags/tag\")\n  end\nend\n",
      "app/views/orders/tags/tag.html.erb" => "<p>出貨標籤</p>\n",
      "app/actors/orders/validate.rb" => "class Orders::Validate < Actor\n  def call\n    PrintOrderTagJob.perform_later\n  end\nend\n",
    )
    @catalog = ScreenCatalog.call(snapshot: @snapshot)
    @analysis.changed_files.create!(file_path: "app/views/orders/tags/tag.html.erb", change_type: "modified")

    mapping = locate.fetch("app/views/orders/tags/tag.html.erb")

    assert_equal [ "orders#new" ], mapping.screen_keys
    assert_match "PrintOrderTagJob", mapping.trace.first
  end

  test "a class-level model change is followed through the actors that use it when no controller names it" do
    @snapshot = screen_fixture_snapshot(
      "app/models/order_line.rb" => "class OrderLine < ApplicationRecord\nend\n",
      "app/actors/orders/validate.rb" => "class Orders::Validate < Actor\n  def call\n    OrderLine.where(order:)\n  end\nend\n",
    )
    @catalog = ScreenCatalog.call(snapshot: @snapshot)
    change_entity("app/models/order_line.rb", "model", "OrderLine")

    assert_equal [ "orders#new" ], locate.fetch("OrderLine").screen_keys
  end

  test "finds callers that name the class with a leading :: (top-level constant)" do
    @snapshot = screen_fixture_snapshot(
      "app/actors/orders/create.rb" => "class Orders::Create < Actor\n  def call\n    ::Orders::Validate.call(order:)\n  end\nend\n",
    )
    @catalog = ScreenCatalog.call(snapshot: @snapshot)
    change_entity("app/actors/orders/validate.rb", "actor", "Orders::Validate", "check_qty")

    mapping = locate.fetch("Orders::Validate#check_qty")
    assert_nil mapping.bucket
    assert_equal [ "orders#new" ], mapping.screen_keys
  end
end
