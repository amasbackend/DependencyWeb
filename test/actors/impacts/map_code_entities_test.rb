require "test_helper"

class Impacts::MapCodeEntitiesTest < ActiveSupport::TestCase
  # Same caller-chain shape as GraphifyGraphIndexTest: Order#ship! (changed)
  # ← Orders::Ship#call (direct) ← OrdersController#ship / #cancel (indirect),
  # plus Orders::Refund#call, a sibling consumer of a different Order method
  # entirely — proves regression_candidate detection (§2's reused
  # "model_consumer" concept) and, since no matching CodeEntity is seeded for
  # it, that a graph hit with no base-index match is flagged for review
  # rather than silently dropped or guessed at (§36).
  def sample_graph
    {
      "nodes" => [
        { "id" => "model_order", "label" => "Order", "source_file" => "app/models/order.rb", "_callable_class" => true },
        { "id" => "model_order_ship", "label" => ".ship!()", "source_file" => "app/models/order.rb" },
        { "id" => "model_order_status", "label" => ".status()", "source_file" => "app/models/order.rb" },
        { "id" => "actor_ship", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "_callable_class" => true },
        { "id" => "actor_ship_call", "label" => ".call()", "source_file" => "app/actors/orders/ship.rb" },
        { "id" => "actor_refund", "label" => "Orders::Refund", "source_file" => "app/actors/orders/refund.rb", "_callable_class" => true },
        { "id" => "actor_refund_call", "label" => ".call()", "source_file" => "app/actors/orders/refund.rb" },
        { "id" => "controller_orders", "label" => "OrdersController", "source_file" => "app/controllers/orders_controller.rb", "_callable_class" => true },
        { "id" => "controller_orders_ship", "label" => ".ship()", "source_file" => "app/controllers/orders_controller.rb" },
        { "id" => "controller_orders_cancel", "label" => ".cancel()", "source_file" => "app/controllers/orders_controller.rb" },
      ],
      "links" => [
        { "source" => "actor_ship_call", "target" => "model_order_ship", "relation" => "calls", "confidence" => "EXTRACTED", "confidence_score" => 1 },
        { "source" => "controller_orders_ship", "target" => "actor_ship_call", "relation" => "calls", "confidence" => "EXTRACTED", "confidence_score" => 1 },
        { "source" => "controller_orders_cancel", "target" => "actor_ship_call", "relation" => "calls", "confidence" => "EXTRACTED", "confidence_score" => 1 },
        { "source" => "actor_refund_call", "target" => "model_order_status", "relation" => "calls", "confidence" => "EXTRACTED", "confidence_score" => 1 },
      ],
    }
  end

  def build_scenario
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")

    order_ship = project.code_entities.create!(
      entity_type: "model", name: "Order#ship!", class_name: "Order", method_name: "ship!",
      file_path: "app/models/order.rb", signature_hash: "sig-order-ship",
    )
    project.code_entities.create!(
      entity_type: "actor", name: "Orders::Ship#call", class_name: "Orders::Ship", method_name: "call",
      file_path: "app/actors/orders/ship.rb", signature_hash: "sig-orders-ship",
    )
    project.code_entities.create!(
      entity_type: "controller", name: "OrdersController#ship", class_name: "OrdersController", method_name: "ship",
      file_path: "app/controllers/orders_controller.rb", signature_hash: "sig-orders-controller-ship",
    )
    project.code_entities.create!(
      entity_type: "controller", name: "OrdersController#cancel", class_name: "OrdersController", method_name: "cancel",
      file_path: "app/controllers/orders_controller.rb", signature_hash: "sig-orders-controller-cancel",
    )
    # Deliberately no CodeEntity seeded for Orders::Refund#call — simulates a
    # real consumer Graphify found that isn't (yet) in the base index.

    pull_request_analysis = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    pull_request_analysis.graphify_artifacts.create!(
      format: "graph_json", raw_content: "{}", parsed_content: sample_graph, graphify_version: "0.0.0-test",
    )
    changed_file = pull_request_analysis.changed_files.create!(
      file_path: "app/models/order.rb", change_type: "modified", additions: 1, deletions: 0,
    )
    pull_request_analysis.changed_code_entities.create!(
      changed_file: changed_file, code_entity: order_ship, entity_type: "model",
      class_name: "Order", method_name: "ship!", change_kind: "modified",
    )

    pull_request_analysis
  end

  test "classifies direct change, direct/indirect dependency, and regression candidates from the real graph" do
    pra = build_scenario

    result = Impacts::MapCodeEntities.result(pull_request_analysis: pra)

    assert result.success?
    pra.reload
    assert_equal "mapping_features", pra.status

    items = pra.impact_items.includes(:code_entity)
    assert_equal result.impact_items_count, items.count

    change_item = items.find { |i| i.impact_level == "direct_change" }
    assert_equal "Order", change_item.code_entity.class_name
    assert_not change_item.needs_manual_review

    direct = items.select { |i| i.impact_level == "direct_dependency" }
    assert_equal [ "Orders::Ship" ], direct.map { |i| i.code_entity.class_name }

    indirect = items.select { |i| i.impact_level == "indirect_dependency" }
    assert_equal [ "OrdersController", "OrdersController" ], indirect.map { |i| i.code_entity.class_name }.sort
    assert_equal [ "cancel", "ship" ], indirect.map { |i| i.code_entity.method_name }.sort

    regression = items.select { |i| i.impact_level == "regression_candidate" }
    assert_equal 1, regression.size
    assert_nil regression.first.code_entity_id
    assert regression.first.needs_manual_review
    assert_equal "Order", regression.first.evidence["shared_model"]
  end

  test "still records a direct_change item when the entity has no graph representation" do
    pra = build_scenario
    # A changed route/view has no graph node at all — code_entity_id is also
    # nil here since nothing in the base index matches a plain route line.
    pra.changed_code_entities.create!(
      changed_file: pra.changed_files.first, entity_type: "route", change_kind: "modified",
    )

    result = Impacts::MapCodeEntities.result(pull_request_analysis: pra)

    assert result.success?
    route_item = pra.impact_items.where(code_entity_id: nil, impact_level: "direct_change").first
    assert route_item.present?
    assert route_item.needs_manual_review
  end

  test "re-running replaces stale impact items rather than duplicating them" do
    pra = build_scenario

    first = Impacts::MapCodeEntities.result(pull_request_analysis: pra)
    assert first.success?
    first_count = pra.impact_items.count

    second = Impacts::MapCodeEntities.result(pull_request_analysis: pra)

    assert second.success?
    assert_equal first_count, pra.impact_items.count
  end

  test "fails cleanly when no graphify artifact exists yet" do
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou")
    pra = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")

    result = Impacts::MapCodeEntities.result(pull_request_analysis: pra)

    assert_not result.success?
    pra.reload
    assert_equal "failed", pra.status
    assert_equal "mapping_features", pra.error_stage
  end
end
