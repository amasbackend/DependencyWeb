class ProjectsController < ApplicationController
  PER_PAGE = 25

  before_action :set_project, only: [ :show, :destroy, :sync ]

  def create
    actor = Projects::Create.result(
      owner: project_params[:owner], repository_name: project_params[:repository_name],
      default_branch: project_params[:default_branch].presence,
    )

    if actor.success? && actor.already_imported
      redirect_to root_path, notice: t(".already_imported", name: actor.project.github_full_name)
    elsif actor.success?
      redirect_to root_path, notice: t(".success")
    else
      redirect_to root_path, alert: actor.error
    end
  end

  def show
    @query = params[:q].presence
    @view = params[:view] == "technical" ? "technical" : "business"
    like_query = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%" if @query

    features_scope = @project.business_features.joins(:business_module).includes(:business_module, operator_path: :segments)
    features_scope = features_scope.includes(:code_entities) if @view == "technical"
    features_scope = features_scope.where(
      "business_features.name LIKE :q OR business_features.domain_action LIKE :q", q: like_query,
    ) if @query

    @business_features_count = features_scope.count
    @page = [ params[:page].to_i, 1 ].max
    @total_pages = [ (@business_features_count.to_f / PER_PAGE).ceil, 1 ].max
    @business_features = features_scope
      .order("business_modules.name ASC, business_features.name ASC")
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE)

    return unless @query

    @matched_code_entities = @project.code_entities
      .where("name LIKE :q OR file_path LIKE :q OR class_name LIKE :q", q: like_query)
      .order(:entity_type, :name).limit(50)
  end

  def sync
    actor = Projects::Sync.result(project: @project)

    if actor.success?
      redirect_to project_path(@project), notice: t(".success")
    else
      redirect_to project_path(@project), alert: actor.error
    end
  end

  def destroy
    @project.destroy!
    cleanup_repository_directory(@project)
    redirect_to root_path, notice: t(".success")
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:owner, :repository_name, :default_branch)
  end

  # Best-effort — the DB record (the source of truth) is already gone by the
  # time this runs, so a cleanup failure here is a disk-space leak, not a
  # data-integrity problem; log and move on rather than blocking the redirect.
  def cleanup_repository_directory(project)
    root = Rails.application.config.x.repository_root || REPOSITORY_ROOT
    dir = File.join(root, project.owner, project.repository_name)
    FileUtils.remove_entry(dir) if File.directory?(dir)
  rescue StandardError => e
    Rails.logger.error("[ProjectsController#destroy] failed to remove #{dir}: #{e.message}")
  end
end
