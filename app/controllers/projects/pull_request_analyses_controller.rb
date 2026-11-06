module Projects
  class PullRequestAnalysesController < Projects::BaseController
    before_action :set_project

    def create
      pr_number = pr_number_param
      if pr_number.nil?
        redirect_to project_path(@project), alert: t(".invalid_pr_number") and return
      end

      actor = PullRequests::PrepareAnalysis.result(project: @project, pr_number: pr_number)

      if actor.success?
        redirect_to project_pull_request_analysis_path(@project, actor.pull_request_analysis), notice: t(".success")
      else
        redirect_to project_path(@project), alert: actor.error
      end
    end

    # Three tabs, one per audience: 測試範圍 for QC/operators (the default —
    # §42: whoever opens this page should land on what they're here for),
    # 程式異動 (what changed: files, methods, diff) and 影響範圍 (what it
    # reaches: screens, dependents, Graphify graph) for engineers.
    TABS = %w[test_scope changes impact].freeze

    # The six pre-merge tabs, so old links/bookmarks land on their new home.
    LEGACY_TABS = {
      "raw_diff" => "changes", "business" => "impact", "technical" => "impact", "graphify" => "impact",
    }.freeze

    # Graphify graph views: "pr" = depth-capped impact subgraph, "project" =
    # the whole graph.json with this PR's nodes highlighted.
    GRAPH_SCOPES = %w[pr project].freeze

    def show
      @pull_request_analysis = @project.pull_request_analyses.find(params[:id])
      # Latest *completed* report — a failed run is kept only for its cost.
      @test_report = @pull_request_analysis.test_reports.where(status: "completed").order(created_at: :desc).first
      requested_tab = LEGACY_TABS.fetch(params[:tab].to_s, params[:tab])
      @tab = TABS.include?(requested_tab) ? requested_tab : "test_scope"

      load_impact_items if @tab == "impact"
    end

    # §78 step 15: 可以下載／查看 Markdown Test Report — the show page already
    # covers "查看" (view, inside the 測試範圍 tab); this covers "下載" (download)
    # as a plain file attachment, no separate JS/rendering needed.
    def report
      pull_request_analysis = @project.pull_request_analyses.find(params[:id])
      test_report = pull_request_analysis.test_reports.where(status: "completed").order(created_at: :desc).first

      if test_report&.markdown_content.present?
        send_data test_report.markdown_content,
          filename: "PR#{pull_request_analysis.pr_number}-test-scope.md", type: "text/markdown"
      else
        redirect_to project_pull_request_analysis_path(@project, pull_request_analysis), alert: t(".not_ready")
      end
    end

    # The Graphify tab's iframe content: Graphify's own graph.html (see
    # GraphifyHtmlRenderer), for either the PR's depth-capped impact subgraph
    # (default) or the whole project graph with the PR's nodes highlighted.
    def graph
      pull_request_analysis = @project.pull_request_analyses.find(params[:id])
      artifact = pull_request_analysis.graphify_artifacts.find_by(format: "graph_json")
      return head(:not_found) if artifact&.parsed_content.blank?

      scope = GRAPH_SCOPES.include?(params[:scope]) ? params[:scope] : "pr"
      depth = graph_depth_param
      return unless stale?(etag: [ artifact, scope, depth ])

      subgraph = GraphifySubgraphBuilder.call(
        pull_request_analysis: pull_request_analysis, index: GraphifyGraphIndex.new(artifact.parsed_content), max_depth: depth,
      )
      html = GraphifyHtmlRenderer.call(
        graph_json: artifact.parsed_content, title: "PR-#{pull_request_analysis.pr_number}-#{scope}",
        node_ids: scope == "pr" ? subgraph[:node_ids] : nil, seed_ids: subgraph[:seed_ids], direct_ids: subgraph[:direct_ids],
      )
      render html: html.html_safe, layout: false
    rescue GraphifyCli::Error => e
      render plain: t(".render_failed", message: e.message), status: :internal_server_error
    end

    private

    # Impact items grouped under the changed class/method they stem from, so
    # 影響範圍 reads "this change → what it reaches" instead of one flat list.
    def load_impact_items
      @impact_level_filter = params[:impact_level] if ImpactItem.impact_level.values.include?(params[:impact_level])
      scope = @pull_request_analysis.impact_items
        .includes(:code_entity, business_feature: [ :business_module, { operator_path: :segments } ])
      scope = scope.where(impact_level: @impact_level_filter) if @impact_level_filter
      @impact_items_by_source = scope.to_a.group_by(&:source_changed_code_entity_id)
      @impact_level_counts = @pull_request_analysis.impact_items.group(:impact_level).count
    end

    def graph_depth_param
      params[:depth].presence&.to_i&.clamp(1, 3) || GraphifySubgraphBuilder::DEFAULT_DEPTH
    end

    def set_project
      @project = Project.find(params[:project_id])
    end

    # §64: PR Number must be integer-only — reject anything else outright
    # rather than coercing (e.g. `.to_i` on "65abc" would silently become 65).
    def pr_number_param
      raw = params[:pr_number].to_s.strip
      raw.match?(/\A\d+\z/) ? raw.to_i : nil
    end
  end
end
