module Projects
  # Renders the Graphify tab's Inspector panel for one node, fetched lazily
  # (a Turbo Frame `src` set by graphify_frame_controller.js when a node is
  # opened inside the embedded Graphify graph.html) — adds the app-side
  # detail Graphify itself can't know, such as mapped business features.
  class GraphifyNodesController < Projects::BaseController
    before_action :set_project
    before_action :set_pull_request_analysis
    before_action :set_index

    # Same reverse-BFS depth Impacts::MapCodeEntities uses for impact
    # classification — "Indirect" here means "the rest of what's reachable
    # within that same bound", not an arbitrary different number.
    MAX_DEPTH = 5

    def show
      @node_id = params[:id]
      @node = @index.node(@node_id)
      @entity_type = @index.entity_type_for(@node_id)
      @class_name = @index.class_name_for(@node_id)
      @method_name = @index.method_name_for(@node_id)
      @community_name = @index.community_name_for(@node_id)
      @direct_inbound = @index.direct_callers_of(@node_id).size
      @total_inbound = @index.reverse_bfs(@node_id, max_depth: MAX_DEPTH).size
      @code_entity = resolve_code_entity
      @business_features = @code_entity&.business_features || BusinessFeature.none
    end

    private

    def set_project
      @project = Project.find(params[:project_id])
    end

    def set_pull_request_analysis
      @pull_request_analysis = @project.pull_request_analyses.find(params[:pull_request_analysis_id])
    end

    def set_index
      artifact = @pull_request_analysis.graphify_artifacts.find_by(format: "graph_json")
      @index = GraphifyGraphIndex.new(artifact&.parsed_content || {})
    end

    def resolve_code_entity
      return nil unless @entity_type

      @project.code_entities.find_by(entity_type: @entity_type, class_name: @class_name, method_name: @method_name)
    end
  end
end
