require "test_helper"

class GraphifySubgraphBuilderTest < ActiveSupport::TestCase
  # A -> B -> C -> D -> E (each "calls" the next, i.e. link source calls target;
  # GraphifyGraphIndex#reverse_bfs walks from a node back to its *callers*).
  # Modeled on the real graph.json node/link shape confirmed in dev data
  # (id/label/source_file/_callable_class on nodes; source/target/relation on
  # links), not a simplified stand-in shape.
  def graph_json
    communities = { "a" => [ 1, "Core" ], "b" => [ 1, "Core" ], "c" => [ 2, nil ], "d" => [ 2, nil ], "e" => [ nil, nil ] }
    nodes = %w[a b c d e].map do |id|
      community_id, community_name = communities[id]
      {
        "id" => id, "label" => id.upcase, "source_file" => "app/actors/#{id}.rb", "_callable_class" => true,
        "community" => community_id, "community_name" => community_name,
      }
    end
    links = [
      { "source" => "a", "target" => "b", "relation" => "calls" },
      { "source" => "b", "target" => "c", "relation" => "calls" },
      { "source" => "c", "target" => "d", "relation" => "calls" },
      { "source" => "d", "target" => "e", "relation" => "calls" },
    ]
    { "nodes" => nodes, "links" => links }
  end

  def build_pull_request_analysis(changed_class_name:)
    project = Project.create!(owner: "AMASTek", repository_name: "PrjJieZhou#{rand(1_000_000)}", status: "ready")
    analysis = project.pull_request_analyses.create!(pr_number: 65, status: "graphifying")
    changed_file = analysis.changed_files.create!(file_path: "app/actors/#{changed_class_name.downcase}.rb", change_type: "modified")
    analysis.changed_code_entities.create!(
      changed_file: changed_file, entity_type: "actor", class_name: changed_class_name, change_kind: "modified",
    )
    analysis
  end

  test "includes only the changed node itself at depth 0 (no callers to walk)" do
    analysis = build_pull_request_analysis(changed_class_name: "A")
    index = GraphifyGraphIndex.new(graph_json)

    subgraph = GraphifySubgraphBuilder.call(pull_request_analysis: analysis, index: index, max_depth: 2)

    assert_equal({ node_ids: [ "a" ], seed_ids: [ "a" ], direct_ids: [] }, subgraph)
  end

  test "walks reverse dependencies (callers) up to max_depth, separating seed and direct callers" do
    # C is called by B, which is called by A — reverse BFS from "c" reaches b (depth 1) and a (depth 2).
    analysis = build_pull_request_analysis(changed_class_name: "C")
    index = GraphifyGraphIndex.new(graph_json)

    subgraph = GraphifySubgraphBuilder.call(pull_request_analysis: analysis, index: index, max_depth: 2)

    assert_equal %w[a b c], subgraph[:node_ids].sort
    assert_equal [ "c" ], subgraph[:seed_ids]
    assert_equal [ "b" ], subgraph[:direct_ids]
  end

  test "does not walk past max_depth (the actual depth-cap guarantee)" do
    # From "c": depth 1 = b, depth 2 = a. With max_depth 1, "a" must be excluded.
    analysis = build_pull_request_analysis(changed_class_name: "C")
    index = GraphifyGraphIndex.new(graph_json)

    subgraph = GraphifySubgraphBuilder.call(pull_request_analysis: analysis, index: index, max_depth: 1)

    assert_includes subgraph[:node_ids], "b"
    assert_not_includes subgraph[:node_ids], "a"
  end

  test "returns no nodes when the changed entity has no graph representation" do
    analysis = build_pull_request_analysis(changed_class_name: "NoSuchClass")
    index = GraphifyGraphIndex.new(graph_json)

    subgraph = GraphifySubgraphBuilder.call(pull_request_analysis: analysis, index: index, max_depth: 2)

    assert_equal({ node_ids: [], seed_ids: [], direct_ids: [] }, subgraph)
  end

  test "adds each node's structural parent so method nodes render under their class" do
    # "a_ship" is a method defined on class node "a" (a "method" edge, not a
    # dependency) and is called by "b" — the subgraph must pull in "a" too.
    graph = graph_json
    graph["nodes"] << { "id" => "a_ship", "label" => ".ship()", "source_file" => "app/actors/a.rb" }
    graph["links"] += [
      { "source" => "a", "target" => "a_ship", "relation" => "method" },
      { "source" => "b", "target" => "a_ship", "relation" => "calls" },
    ]
    analysis = build_pull_request_analysis(changed_class_name: "A")
    analysis.changed_code_entities.first.update!(method_name: "ship")
    index = GraphifyGraphIndex.new(graph)

    subgraph = GraphifySubgraphBuilder.call(pull_request_analysis: analysis, index: index, max_depth: 1)

    assert_equal [ "a_ship" ], subgraph[:seed_ids]
    assert_equal [ "b" ], subgraph[:direct_ids]
    assert_equal %w[a a_ship b], subgraph[:node_ids].sort
  end
end
