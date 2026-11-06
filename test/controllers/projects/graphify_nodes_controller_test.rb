require "test_helper"

class Projects::GraphifyNodesControllerTest < ActionDispatch::IntegrationTest
  # Order#ship! (called by) Orders::Ship#call (called by) OrdersController#ship
  # and #cancel — same shape as Impacts::MapCodeEntitiesTest, so inspecting
  # "actor_ship_call" has 2 direct callers and the same 2 total (max_depth 5
  # doesn't add anything further in this small fixture).
  def sample_graph
    {
      "nodes" => [
        { "id" => "actor_ship", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "_callable_class" => true },
        { "id" => "actor_ship_call", "label" => ".call()", "source_file" => "app/actors/orders/ship.rb", "community" => 1, "community_name" => "Orders" },
        { "id" => "controller_orders", "label" => "OrdersController", "source_file" => "app/controllers/orders_controller.rb", "_callable_class" => true },
        { "id" => "controller_orders_ship", "label" => ".ship()", "source_file" => "app/controllers/orders_controller.rb" },
        { "id" => "controller_orders_cancel", "label" => ".cancel()", "source_file" => "app/controllers/orders_controller.rb" },
      ],
      "links" => [
        { "source" => "controller_orders_ship", "target" => "actor_ship_call", "relation" => "calls" },
        { "source" => "controller_orders_cancel", "target" => "actor_ship_call", "relation" => "calls" },
      ],
    }
  end

  def build_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou", status: "ready")
    business_module = project.business_modules.create!(name: "訂單", slug: "orders")
    feature = business_module.business_features.create!(project: project, name: "出貨", slug: "ship", domain_action: "ship")

    code_entity = project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-1",
    )
    FeatureCodeEntity.create!(business_feature: feature, code_entity: code_entity, role: "controller_action")

    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    analysis.graphify_artifacts.create!(
      format: "graph_json", raw_content: "{}", graphify_version: "0.0.0-test", parsed_content: sample_graph,
    )

    [ project, analysis ]
  end

  test "show renders type, file, business feature, and real inbound counts" do
    project, analysis = build_scenario

    get project_pull_request_analysis_graphify_node_path(project, analysis, "actor_ship_call")

    assert_response :success
    assert_select "turbo-frame#graph-inspector" do
      assert_select "dd", text: "Actor"
      assert_select "dd", text: "app/actors/orders/ship.rb"
      assert_select "dd", text: "出貨"
      assert_select "dd", text: "Orders" # community name, already computed by Graphify's own clustering
      assert_select "dd", text: "2" # direct inbound: #ship and #cancel both call it directly
    end
  end

  test "show renders a not-found state for an unknown node id" do
    project, analysis = build_scenario

    get project_pull_request_analysis_graphify_node_path(project, analysis, "no-such-node")

    assert_response :success
    assert_match "找不到此節點", response.body
  end

  test "show renders 尚未對應 when the node has no linked business feature" do
    project, analysis = build_scenario

    get project_pull_request_analysis_graphify_node_path(project, analysis, "controller_orders_ship")

    assert_response :success
    assert_match "尚未對應", response.body
  end
end
