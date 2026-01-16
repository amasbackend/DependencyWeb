# frozen_string_literal: true

class CodeAnalysisController < ApplicationController
  def new
    # 顯示匯入頁面
  end

  def create
    result = CodeAnalysis::ImportFromGithub.result(
      owner: params[:owner],
      repo: params[:repo],
      branch: params[:branch] || "main",
    )

    if result.success?
      render json: {
        success: true,
        message: result.message,
        company_id: result.company&.id,
        statistics: result.statistics,
      }
    else
      render json: {
        success: false,
        error: result.error,
      }, status: :unprocessable_entity
    end
  end
end
