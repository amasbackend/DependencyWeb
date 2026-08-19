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

    def show
      @pull_request_analysis = @project.pull_request_analyses.find(params[:id])
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
