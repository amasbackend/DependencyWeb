require "test_helper"

class GraphifyGraphIndexTest < ActiveSupport::TestCase
  # A → B → C caller chain (mirrors project_plan.md §30's own example: A3
  # Cooling → UpdateUsageActor → Wms::Stock::UpdateActor), plus a sibling D
  # that also calls B but isn't on the path to C, to prove the BFS doesn't
  # over-collect.
  def sample_graph
    {
      "nodes" => [
        { "id" => "model_order", "label" => "Order", "source_file" => "app/models/order.rb", "_callable_class" => true },
        { "id" => "model_order_ship", "label" => ".ship!()", "source_file" => "app/models/order.rb" },
        { "id" => "actor_ship", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "_callable_class" => true },
        { "id" => "actor_ship_call", "label" => ".call()", "source_file" => "app/actors/orders/ship.rb" },
        { "id" => "controller_orders", "label" => "OrdersController", "source_file" => "app/controllers/orders_controller.rb", "_callable_class" => true },
        { "id" => "controller_orders_ship", "label" => ".ship()", "source_file" => "app/controllers/orders_controller.rb" },
        { "id" => "controller_orders_cancel", "label" => ".cancel()", "source_file" => "app/controllers/orders_controller.rb" },
        { "id" => "model_order_status", "label" => ".status()", "source_file" => "app/models/order.rb" },
        { "id" => "actor_refund_call", "label" => ".call()", "source_file" => "app/actors/orders/refund.rb" },
      ],
      "links" => [
        { "source" => "actor_ship_call", "target" => "model_order_ship", "relation" => "calls", "confidence" => "EXTRACTED" },
        { "source" => "controller_orders_ship", "target" => "actor_ship_call", "relation" => "calls", "confidence" => "EXTRACTED" },
        { "source" => "controller_orders_cancel", "target" => "actor_ship_call", "relation" => "calls", "confidence" => "EXTRACTED" },
        # Orders::Refund calls a *different* Order method — not on the ship!
        # call chain at all, but still a consumer of the same model class.
        { "source" => "actor_refund_call", "target" => "model_order_status", "relation" => "calls", "confidence" => "EXTRACTED" },
        # Structural edges — real Graphify output includes these alongside
        # genuine calls: the class "containing" its own method, and the file
        # "containing" the class. Neither is a dependency.
        { "source" => "model_order", "target" => "model_order_ship", "relation" => "method", "confidence" => "EXTRACTED" },
        { "source" => "model_order", "target" => "model_order_status", "relation" => "method", "confidence" => "EXTRACTED" },
      ],
    }
  end

  test "node_id_for resolves both class-level and method-level nodes by identity" do
    index = GraphifyGraphIndex.new(sample_graph)

    assert_equal "model_order", index.node_id_for(class_name: "Order", method_name: nil)
    assert_equal "model_order_ship", index.node_id_for(class_name: "Order", method_name: "ship!")
    assert_nil index.node_id_for(class_name: "NoSuchClass", method_name: "x")
  end

  test "entity_type_for classifies via the same Rails-directory convention as the base index" do
    index = GraphifyGraphIndex.new(sample_graph)

    assert_equal "model", index.entity_type_for("model_order_ship")
    assert_equal "actor", index.entity_type_for("actor_ship_call")
    assert_equal "controller", index.entity_type_for("controller_orders_ship")
  end

  test "reverse_bfs walks the caller chain with correct hop depth and real edge evidence" do
    index = GraphifyGraphIndex.new(sample_graph)

    result = index.reverse_bfs("model_order_ship", max_depth: 5)

    assert_equal 1, result["actor_ship_call"][:depth]
    assert_equal 2, result["controller_orders_ship"][:depth]
    assert_equal 2, result["controller_orders_cancel"][:depth]
    # Path evidence traces the real chain back, not just a bare number —
    # ordered outward from the changed node (nearest edge first).
    assert_equal [ "model_order_ship", "actor_ship_call" ],
      result["controller_orders_ship"][:path].map { |edge| edge["target"] }
  end

  test "reverse_bfs respects max_depth" do
    index = GraphifyGraphIndex.new(sample_graph)

    result = index.reverse_bfs("model_order_ship", max_depth: 1)

    assert result.key?("actor_ship_call")
    assert_not result.key?("controller_orders_ship")
  end

  test "callers_of_class finds a consumer of a different method on the same class" do
    index = GraphifyGraphIndex.new(sample_graph)

    callers = index.callers_of_class("Order").map { |edge| edge["source"] }

    assert_includes callers, "actor_ship_call"    # calls Order#ship!
    assert_includes callers, "actor_refund_call"  # calls Order#status — different method, same class
  end

  test "ignores structural method/contains edges — a class defining a method is not a caller of it" do
    index = GraphifyGraphIndex.new(sample_graph)

    result = index.reverse_bfs("model_order_ship", max_depth: 5)

    # Real bug found in live validation (Phase 11): a class's own "method"
    # edge to its method previously showed up as a false direct_dependency
    # hit for *every* changed method, since it targets the exact same node.
    assert_not result.key?("model_order")
    assert_empty index.callers_of_class("Order").select { |e| e["relation"] == "method" }
  end
end
