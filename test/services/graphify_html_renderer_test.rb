require "test_helper"

class GraphifyHtmlRendererTest < ActiveSupport::TestCase
  def graph
    {
      "nodes" => [
        { "id" => "a", "label" => "Orders::Ship", "source_file" => "app/actors/orders/ship.rb", "community" => 0, "community_name" => "Ship" },
        { "id" => "b", "label" => "OrdersController", "source_file" => "app/controllers/orders_controller.rb", "community" => 1, "community_name" => "Controllers" },
        { "id" => "c", "label" => "Unrelated", "source_file" => "app/models/unrelated.rb" },
      ],
      "links" => [ { "source" => "b", "target" => "a", "relation" => "calls", "confidence" => "EXTRACTED" } ],
    }
  end

  test "renders Graphify's own vis.js graph.html, restricted to node_ids when given" do
    html = GraphifyHtmlRenderer.call(graph_json: graph, title: "PR-1", node_ids: %w[a b], seed_ids: %w[a], direct_ids: %w[b])

    assert_match "vis-network", html
    assert_match "2 nodes", html
    assert_match "Controllers", html
    assert_match 'const SEED_IDS = ["a"]', html
    assert_no_match(/Unrelated/, html)
  end

  test "renders the whole graph when node_ids is nil, bucketing community-less nodes under 其他" do
    html = GraphifyHtmlRenderer.call(graph_json: graph, title: "PR-1")

    assert_match "3 nodes", html
    assert_match '{"cid": -1, "color": "#BAB0AC", "label": "\\u5176\\u4ed6"', html # "其他", JSON-escaped
  end
end
