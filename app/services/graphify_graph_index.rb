# Indexes one PR's Graphify graph.json (§29 — node-link JSON: top-level
# "nodes"/"links", each link carrying source/target node ids plus
# relation/confidence) so §30-31's cross-referencing (Impacts::MapCodeEntities)
# can (a) find the graph node for a changed entity, given the same
# class_name/method_name identity already stored on CodeEntity/ChangedCodeEntity,
# and (b) walk "who depends on this" by reversing the edges — Graphify's
# nodes are the *callee*, so a link's source is the caller and its target is
# the callee; finding dependents of a node means finding links whose target
# is that node.
#
# Reuses CodeEntityExtractor's own Rails-path classification and method-label
# regex so a node resolves to the same class_name/method_name identity here
# as when the base code index (Phase 5) first classified it — the whole
# point is being able to match the two back up.
class GraphifyGraphIndex
  # Real graph.json output (confirmed against AMASTek/PrjJieZhou) mixes
  # genuine dependency edges ("calls", "inherits", "mixes_in", "extends")
  # with purely structural ones Graphify uses to encode the AST itself —
  # "method" (class → its own method, i.e. "this class defines this method")
  # and "contains" (file → class). A structural edge is not a dependency:
  # naively treating "target: <method>, relation: method" from its own
  # enclosing class as a "caller" produced false direct_dependency hits in
  # real testing — every method looked like it was "called by" the class
  # that merely defines it. "imports"/"imports_from" (load-time) and
  # "rationale_for" (a Graphify semantic annotation, not a code relation)
  # are excluded too — too weak/unclear a signal to assert an impact from.
  DEPENDENCY_RELATIONS = %w[calls inherits mixes_in extends].freeze

  def initialize(parsed_content)
    @nodes = parsed_content.fetch("nodes", [])
    @links = parsed_content.fetch("links", []).select { |l| DEPENDENCY_RELATIONS.include?(l["relation"]) }
  end

  # Resolves a changed/known entity's graph node id from the same identity
  # fields already stored on CodeEntity/ChangedCodeEntity. Returns nil if the
  # entity has no graph representation at all (routes/views — Graphify never
  # produces nodes for those; see CodeEntityExtractor) or wasn't found (a
  # brand-new entity the PR itself introduces has no *callers* to trace, so
  # a miss here is expected, not an error).
  def node_id_for(class_name:, method_name:)
    key_to_node_id[[class_name, method_name]]
  end

  def node(node_id)
    nodes_by_id[node_id]
  end

  # Rails entity_type for a node, via the same directory-prefix convention
  # as CodeEntityExtractor — nil if the node falls outside recognized Rails
  # directories (Graphify itself has no notion of Rails conventions).
  def entity_type_for(node_id)
    file_path = node(node_id)&.dig("source_file")
    return nil if file_path.blank?

    CodeEntityExtractor::TYPE_BY_PATH_PREFIX.each { |prefix, type| return type if file_path.start_with?(prefix) }
    nil
  end

  def class_name_for(node_id)
    n = node(node_id)
    return nil unless n

    n["_callable_class"] ? n["label"] : class_name_by_file[n["source_file"]]
  end

  def method_name_for(node_id)
    match = CodeEntityExtractor::METHOD_LABEL.match(node(node_id)&.dig("label").to_s)
    match && match[:name]
  end

  # Direct (1-hop) callers of a node: links whose target is this node.
  def direct_callers_of(node_id)
    callers_by_target[node_id] || []
  end

  # All node ids belonging to a class (the class node itself plus every
  # method node under it) — used for whole-class "who else consumes this
  # model" queries, since a real call can target either the class node
  # (e.g. `Order.find`) or a specific method node (e.g. `order.ship!`).
  def node_ids_for_class(class_name)
    node_ids_for_class_cache[class_name] || []
  end

  # Direct (1-hop) callers of *any* node belonging to a class.
  def callers_of_class(class_name)
    node_ids_for_class(class_name).flat_map { |id| direct_callers_of(id) }
  end

  # Reverse-dependency BFS from `node_id` — "who (transitively) depends on
  # this", capped at `max_depth` hops so a densely connected real-world graph
  # can't make this unbounded. Returns { caller_node_id => { depth:, path: [edge, edge, ...] } },
  # where `path` is the actual chain of edges, ordered outward from `node_id`
  # (nearest edge first) — real evidence for §40's "分析依據" panel and §36's
  # "never invent, always trace" requirement, not just a bare hop count.
  def reverse_bfs(node_id, max_depth:)
    visited = { node_id => true }
    result = {}
    frontier = [ { id: node_id, path: [] } ]
    depth = 0

    while frontier.any? && depth < max_depth
      depth += 1
      next_frontier = []
      frontier.each do |entry|
        direct_callers_of(entry[:id]).each do |edge|
          source = edge["source"]
          next if visited[source]

          visited[source] = true
          path = entry[:path] + [ edge ]
          result[source] = { depth: depth, path: path }
          next_frontier << { id: source, path: path }
        end
      end
      frontier = next_frontier
    end

    result
  end

  private

  def nodes_by_id
    @nodes_by_id ||= @nodes.index_by { |n| n["id"] }
  end

  def callers_by_target
    @callers_by_target ||= @links.group_by { |l| l["target"] }
  end

  def class_name_by_file
    @class_name_by_file ||= @nodes.each_with_object({}) { |n, h| h[n["source_file"]] ||= n["label"] if n["_callable_class"] }
  end

  def node_ids_for_class_cache
    @node_ids_for_class_cache ||= @nodes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |n, h|
      class_name = n["_callable_class"] ? n["label"] : class_name_by_file[n["source_file"]]
      h[class_name] << n["id"] if class_name
    end
  end

  def key_to_node_id
    @key_to_node_id ||= begin
      index = {}
      @nodes.each do |n|
        next if n["source_file"].blank?

        if n["_callable_class"]
          index[[ n["label"], nil ]] ||= n["id"]
        elsif (match = CodeEntityExtractor::METHOD_LABEL.match(n["label"].to_s))
          index[[ class_name_by_file[n["source_file"]], match[:name] ]] ||= n["id"]
        end
      end
      index
    end
  end
end
