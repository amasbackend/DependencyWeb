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

    # §41's tab set — 測試範圍 (test scope) is the default per §42, deliberately
    # not Raw Diff/修改內容, even though those are the tabs with the longest
    # implementation history — an operator opening this page should land on
    # the thing they're actually here for.
    TABS = %w[test_scope changes business technical graphify raw_diff].freeze

    def show
      @pull_request_analysis = @project.pull_request_analyses.find(params[:id])
      @test_report = @pull_request_analysis.test_reports.order(created_at: :desc).first
      @tab = TABS.include?(params[:tab]) ? params[:tab] : "test_scope"
    end

    # §78 step 15: 可以下載／查看 Markdown Test Report — the show page already
    # covers "查看" (view, inside the 測試範圍 tab); this covers "下載" (download)
    # as a plain file attachment, no separate JS/rendering needed.
    def report
      pull_request_analysis = @project.pull_request_analyses.find(params[:id])
      test_report = pull_request_analysis.test_reports.order(created_at: :desc).first

      if test_report&.markdown_content.present?
        send_data test_report.markdown_content,
          filename: "PR#{pull_request_analysis.pr_number}-test-scope.md", type: "text/markdown"
      else
        redirect_to project_pull_request_analysis_path(@project, pull_request_analysis), alert: t(".not_ready")
      end
    end

    private

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
