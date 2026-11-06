# Picks the depth-capped set of graph nodes around one PR's changed entities
# for the Graphify tab, so it never has to render Graphify's full graph.json
# up front — a real project's graph.json runs to thousands of nodes
# (confirmed: 2,531 nodes / 2,938 links for AMASTek/PrjJieZhou's PR #113),
# far past what a reviewer can usefully look at at once. Only *which* nodes —
# layout, colors and communities are left to Graphify's own exporter (see
# GraphifyHtmlRenderer).
#
# Reuses GraphifyGraphIndex#reverse_bfs — the same traversal
# Impacts::MapCodeEntities already relies on for impact classification —
# rather than building a second graph-walking implementation. "Who does this
# change affect" (reverse/inbound) is exactly the direction a PR reviewer
# needs to browse; outbound browsing is intentionally out of scope here.
class GraphifySubgraphBuilder
  DEFAULT_DEPTH = 2

  def self.call(pull_request_analysis:, index:, max_depth: DEFAULT_DEPTH)
    new(pull_request_analysis, index, max_depth).call
  end

  def initialize(pull_request_analysis, index, max_depth)
    @pull_request_analysis = pull_request_analysis
    @index = index
    @max_depth = max_depth
  end

  # seed_ids: the changed nodes themselves; direct_ids: their 1-hop callers;
  # node_ids: everything to render — all reverse-BFS hits plus each one's
  # structural parent (class/file), so method nodes cluster under their class
  # instead of floating as isolated dots.
  def call
    seed_ids = changed_node_ids
    return { node_ids: [], seed_ids: [], direct_ids: [] } if seed_ids.empty?

    node_depths = seed_ids.index_with { 0 }
    seed_ids.each do |seed_id|
      index.reverse_bfs(seed_id, max_depth: max_depth).each do |node_id, info|
        node_depths[node_id] = [ node_depths[node_id], info[:depth] ].compact.min
      end
    end

    {
      node_ids: (node_depths.keys + index.structural_parent_ids(node_depths.keys)).uniq,
      seed_ids: seed_ids,
      direct_ids: node_depths.select { |_, depth| depth == 1 }.keys,
    }
  end

  private

  attr_reader :pull_request_analysis, :index, :max_depth

  def changed_node_ids
    pull_request_analysis.changed_code_entities.filter_map do |cce|
      index.node_id_for(class_name: cce.class_name, method_name: cce.method_name)
    end.uniq
  end
end
