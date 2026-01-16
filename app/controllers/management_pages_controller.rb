# frozen_string_literal: true

class ManagementPagesController < ApplicationController
  def index
    @companies = Company.all
  end

  def show
    @company = Company.find(params[:id])
    management_pages_scope = @company.management_pages.includes(action_pages: :relate_models)
    action_pages_scope = @company.action_pages.includes(:relate_models)

    # 根據篩選條件調整查詢
    if params[:filter] == "changed"
      # 篩選有變更的 action_pages 或 relate_models
      action_pages_scope = action_pages_scope.left_joins(:relate_models)
                                             .where("action_pages.changed_flag = ? OR relate_models.changed_flag = ?", true, true)
                                             .distinct
    end

    if params[:query].present?
      @action_pages = []
      @management_pages = []
      params[:query].split(",").each do |query_string|
        query = "%#{query_string}%"

        # 搜尋 ActionPage
        @action_pages += action_pages_scope.where("LOWER(action_pages.name) LIKE LOWER(?)", query)
                                           .or(action_pages_scope.where(
                                                 "LOWER(action_pages.relate_action) LIKE LOWER(?)", query
                                               ))
                                           .or(action_pages_scope.where(
                                                 "LOWER(action_pages.relate_model) LIKE LOWER(?)", query
                                               ))
                                           .or(action_pages_scope.where(
                                                 "LOWER(action_pages.select_column) LIKE LOWER(?)", query
                                               ))
                                           .or(action_pages_scope.where(
                                                 "LOWER(action_pages.modify_column) LIKE LOWER(?)", query
                                               ))
                                           .or(action_pages_scope.where(
                                                 "LOWER(action_pages.delete_column) LIKE LOWER(?)", query
                                               ))
                                           .distinct

        # 搜尋 ManagementPage
        @management_pages += management_pages_scope.all.where(id: @action_pages.pluck(:management_page_id))
      end
      @action_pages.uniq!
      @management_pages.uniq!

    else
      @action_pages = action_pages_scope.distinct
      @management_pages = management_pages_scope.distinct
    end
  end

  def reset_flags
    result = GithubAnalysis::ResetFlags.result(company_id: params[:id])

    if result.success?
      render json: {
        success: true,
        message: result.message,
      }
    else
      render json: {
        success: false,
        error: result.error,
      }, status: :unprocessable_entity
    end
  end

  def update_flags_from_pr
    result = GithubAnalysis::UpdateFlags.result(
      owner: params[:owner] || "AMASTek",
      pr_number: params[:pr_number],
      company_id: params[:id],
    )

    if result.success?
      render json: { success: true, message: result.message }
    else
      render json: { success: false, error: result.error }, status: :unprocessable_entity
    end
  end

  def get_pr_info
    owner = params[:owner] || "AMASTek"
    pr_number = params[:pr_number]
    company = Company.find(params[:id])
    repo = company.name

    unless pr_number.present?
      render json: { success: false, error: "PR number 不能為空" }, status: :unprocessable_entity
      return
    end

    github_service = GithubAnalysisService.new
    pr_check = github_service.check_pr_exists(owner, repo, pr_number)

    if pr_check[:exists]
      pr_data = JSON.parse(pr_check[:body])
      render json: {
        success: true,
        title: pr_data["title"],
        html_url: pr_data["html_url"],
        state: pr_data["state"],
        user: pr_data["user"]&.dig("login"),
      }
    else
      render json: {
        success: false,
        error: "PR 不存在或無法存取 (狀態碼: #{pr_check[:status_code]})",
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end
end
