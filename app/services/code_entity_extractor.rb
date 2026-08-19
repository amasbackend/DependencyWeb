require "digest"

# Turns Graphify's graph.json (real tree-sitter output, see docs/architecture_plan.md
# §9) plus a couple of Rails-specific passes (routes.rb, app/views/**) into the
# CodeEntity rows described in project_plan.md §16. Graphify itself has no
# notion of "this is a Rails controller" or "this is a route" — it only knows
# classes/methods/files — so this class supplies the Rails directory-convention
# mapping on top of Graphify's real parsing, rather than reimplementing a Ruby
# parser from scratch.
class CodeEntityExtractor
  TYPE_BY_PATH_PREFIX = {
    "app/models/concerns/" => "concern",
    "app/controllers/concerns/" => "concern",
    "app/actors/concerns/" => "concern",
    "app/models/" => "model",
    "app/controllers/" => "controller",
    "app/actors/" => "actor",
    "app/services/" => "service",
    "app/blueprints/" => "blueprint",
    "app/jobs/" => "job",
    "app/mailers/" => "mailer",
    "app/validators/" => "validator",
    "app/serializers/" => "serializer",
    "app/javascript/" => "javascript",
  }.freeze

  METHOD_LABEL = /\A\.(?<name>[\w?!=\[\]<>+\-\/%]+)\(\)\z/
  ROUTE_LINE = /\A\s*(resources|resource|root|get|post|patch|put|delete|match)\b/

  def self.call(graph_json_path:, worktree_path:)
    new(graph_json_path: graph_json_path, worktree_path: worktree_path).call
  end

  def initialize(graph_json_path:, worktree_path:)
    @graph = JSON.parse(File.read(graph_json_path))
    @worktree_path = worktree_path.to_s
  end

  def call
    class_entities + method_entities + view_entities + route_entities
  end

  private

  attr_reader :worktree_path

  def nodes
    @nodes ||= @graph.fetch("nodes", [])
  end

  def class_nodes
    @class_nodes ||= nodes.select { |n| n["_callable_class"] && classify(n["source_file"]) }
  end

  def class_name_by_file
    @class_name_by_file ||= class_nodes.each_with_object({}) { |n, h| h[n["source_file"]] ||= n["label"] }
  end

  def class_entities
    class_nodes.map { |node| entity_attrs(node, classify(node["source_file"]), node["label"], nil) }
  end

  def method_entities
    nodes.filter_map do |node|
      next unless (type = classify(node["source_file"]))
      next unless (match = METHOD_LABEL.match(node["label"].to_s))

      entity_attrs(node, type, class_name_by_file[node["source_file"]], match[:name])
    end
  end

  def classify(file_path)
    return nil if file_path.blank?

    TYPE_BY_PATH_PREFIX.each { |prefix, type| return type if file_path.start_with?(prefix) }
    nil
  end

  def entity_attrs(node, type, class_name, method_name)
    file_path = node["source_file"]
    {
      entity_type: type,
      name: method_name ? "#{class_name}##{method_name}" : class_name,
      class_name: class_name,
      method_name: method_name,
      file_path: file_path,
      line_start: node["source_location"].to_s.delete_prefix("L").presence&.to_i,
      namespace: class_name.to_s.include?("::") ? class_name.rpartition("::").first : nil,
      signature_hash: Digest::SHA256.hexdigest("#{file_path}:#{class_name}:#{method_name}"),
    }
  end

  # insert_all! requires every hash to share exactly the same set of keys —
  # class/method entities naturally have more attributes than view/route ones,
  # so every entity is normalized through this base shape.
  BLANK_ATTRS = { class_name: nil, method_name: nil, line_start: nil, namespace: nil }.freeze

  def view_entities
    Dir.glob(File.join(worktree_path, "app", "views", "**", "*")).select { |f| File.file?(f) }.map do |abs_path|
      relative = abs_path.delete_prefix("#{worktree_path}/")
      BLANK_ATTRS.merge(
        entity_type: "view",
        name: relative,
        file_path: relative,
        signature_hash: Digest::SHA256.hexdigest("view:#{relative}"),
      )
    end
  end

  def route_entities
    routes_path = File.join(worktree_path, "config", "routes.rb")
    return [] unless File.exist?(routes_path)

    File.readlines(routes_path).each_with_index.filter_map do |line, index|
      next unless ROUTE_LINE.match?(line)

      BLANK_ATTRS.merge(
        entity_type: "route",
        name: line.strip,
        file_path: "config/routes.rb",
        line_start: index + 1,
        signature_hash: Digest::SHA256.hexdigest("route:#{index}:#{line.strip}"),
      )
    end
  end
end
