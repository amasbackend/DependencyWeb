module Impacts
  # §30-31: cross-references this PR's diff (already-parsed ChangedCodeEntity
  # rows, Phase 9) against its Graphify dependency graph (Phase 10) to answer
  # "what else does this change reach" — not just "what changed". Produces
  # ImpactItem rows classified direct_change / direct_dependency /
  # indirect_dependency / regression_candidate (§4 schema). business_feature_id
  # is left nil here — that's Impacts::MapBusinessFeatures' job, run right
  # after this in the same `mapping_features` stage.
  class MapCodeEntities < Actor
    input :pull_request_analysis
    output :impact_items_count

    # Real-world call graphs can be densely connected — an unbounded reverse
    # BFS on a shared low-level helper could pull in a large fraction of the
    # codebase. 5 hops is generous for "does this PR's change plausibly reach
    # here" while keeping the traversal bounded; not a silent cap — every
    # hit is still real graph evidence, just not followed past this depth.
    MAX_DEPTH = 5

    def call
      pull_request_analysis.update!(status: "mapping_features")
      index = GraphifyGraphIndex.new(graph_json)

      items = pull_request_analysis.changed_code_entities.flat_map { |cce| build_items_for(cce, index) }

      PullRequestAnalysis.transaction do
        pull_request_analysis.impact_items.destroy_all
        pull_request_analysis.impact_items.create!(items) if items.any?
      end

      self.impact_items_count = items.size
    rescue StandardError => e
      fail_with(I18n.t("actor.impacts.map_code_entities.failed", message: e.message))
    end

    private

    def project
      pull_request_analysis.project
    end

    def graph_json
      artifact = pull_request_analysis.graphify_artifacts.find_by(format: "graph_json")
      return artifact.parsed_content if artifact&.parsed_content.present?

      fail!(error: I18n.t("actor.impacts.map_code_entities.no_graph"))
    end

    def build_items_for(changed_code_entity, index)
      change_item = direct_change_item(changed_code_entity)

      own_node_id = index.node_id_for(class_name: changed_code_entity.class_name, method_name: changed_code_entity.method_name)
      return [ change_item ] unless own_node_id

      distances = index.reverse_bfs(own_node_id, max_depth: MAX_DEPTH)
      dependency_items = distances.map { |node_id, info| dependency_item(changed_code_entity, index, node_id, info) }
      regression_items = regression_items_for(changed_code_entity, index, own_node_id, distances)

      [ change_item, *dependency_items, *regression_items ]
    end

    def direct_change_item(changed_code_entity)
      {
        source_changed_code_entity_id: changed_code_entity.id,
        code_entity_id: changed_code_entity.code_entity_id,
        impact_level: "direct_change",
        reason: I18n.t("actor.impacts.map_code_entities.direct_change_reason", entity: change_label(changed_code_entity)),
        evidence: { changed_file: changed_code_entity.changed_file.file_path, change_kind: changed_code_entity.change_kind },
        needs_manual_review: changed_code_entity.code_entity_id.nil?,
      }
    end

    def dependency_item(changed_code_entity, index, node_id, info)
      code_entity = resolve_code_entity(index, node_id)
      level = info[:depth] == 1 ? "direct_dependency" : "indirect_dependency"

      {
        source_changed_code_entity_id: changed_code_entity.id,
        code_entity_id: code_entity&.id,
        impact_level: level,
        reason: chain_reason(index, info[:path]),
        evidence: path_evidence(info[:path]),
        needs_manual_review: code_entity.nil?,
      }
    end

    # Reused DependencyWeb concept (docs/architecture_plan.md §2's
    # "model_consumer" priority tier): other code that consumes the same
    # model this change transitively touches, but isn't itself on the call
    # chain from the change — not proven to break, but sharing the same data
    # shape is exactly the kind of thing a deterministic call-graph traversal
    # can miss and a human regression pass should still check.
    def regression_items_for(changed_code_entity, index, own_node_id, distances)
      already_covered = distances.keys.to_set << own_node_id
      touched_model_classes = already_covered.filter_map { |id| index.class_name_for(id) if index.entity_type_for(id) == "model" }.uniq

      touched_model_classes.flat_map do |model_class_name|
        index.callers_of_class(model_class_name).filter_map do |edge|
          caller_id = edge["source"]
          next if already_covered.include?(caller_id)

          already_covered << caller_id
          regression_item(changed_code_entity, index, model_class_name, caller_id, edge)
        end
      end
    end

    def regression_item(changed_code_entity, index, model_class_name, caller_id, edge)
      code_entity = resolve_code_entity(index, caller_id)

      {
        source_changed_code_entity_id: changed_code_entity.id,
        code_entity_id: code_entity&.id,
        impact_level: "regression_candidate",
        reason: I18n.t(
          "actor.impacts.map_code_entities.regression_reason",
          model: model_class_name, entity: node_label(index, caller_id)
        ),
        evidence: { shared_model: model_class_name, relation: edge["relation"] },
        needs_manual_review: code_entity.nil?,
      }
    end

    def resolve_code_entity(index, node_id)
      type = index.entity_type_for(node_id)
      return nil unless type

      project.code_entities.find_by(entity_type: type, class_name: index.class_name_for(node_id), method_name: index.method_name_for(node_id))
    end

    # `path` is ordered outward from the changed node (nearest edge first,
    # see GraphifyGraphIndex#reverse_bfs) — reversed here so the reason reads
    # as an actual call chain, matching project_plan.md §30's own example
    # ("A3 冷卻 ← UpdateUsageActor ← Wms::Stock::UpdateActor" — caller-first).
    def chain_reason(index, path)
      labels = [ node_label(index, path.last["source"]), *path.reverse.map { |edge| node_label(index, edge["target"]) } ]
      I18n.t("actor.impacts.map_code_entities.dependency_reason", chain: labels.join(" → "))
    end

    def path_evidence(path)
      path.map { |edge| edge.slice("source", "target", "relation", "confidence", "confidence_score", "source_file", "source_location") }
    end

    def node_label(index, node_id)
      class_name = index.class_name_for(node_id)
      method_name = index.method_name_for(node_id)
      method_name ? "#{class_name}##{method_name}" : class_name
    end

    def change_label(changed_code_entity)
      changed_code_entity.method_name ? "#{changed_code_entity.class_name}##{changed_code_entity.method_name}" : changed_code_entity.class_name
    end

    def fail_with(message)
      pull_request_analysis.update!(status: "failed", error_message: message, error_stage: "mapping_features")
      Rails.logger.error("[PRAnalysis:#{pull_request_analysis.id}] #{message}")
      fail!(error: message)
    end
  end
end
