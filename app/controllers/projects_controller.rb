class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :destroy, :sync ]

  def create
    actor = Projects::Create.result(
      owner: project_params[:owner], repository_name: project_params[:repository_name],
      default_branch: project_params[:default_branch].presence,
    )

    if actor.success?
      redirect_to root_path, notice: t(".success")
    else
      redirect_to root_path, alert: actor.error
    end
  end

  def show
    @business_modules = @project.business_modules.includes(:business_features).order(:name)
    @query = params[:q].presence
    return unless @query

    like_query = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    @matched_feature_ids = @project.business_features
      .where("name LIKE :q OR domain_action LIKE :q", q: like_query).pluck(:id)
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
