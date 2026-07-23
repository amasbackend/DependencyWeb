# frozen_string_literal: true

class I18nGuidesController < ApplicationController
  RECOMMENDED_BRANCH = "test/i18n"
  SKILL_DIR = ".cursor/skills/relatedoc-i18n"

  def show
    @recommended_branch = RECOMMENDED_BRANCH
    @skill_path = File.join(SKILL_DIR, "SKILL.md")
    @companies = Company.order(:name)
    @selected_company = Company.find_by(id: params[:company_id]) if params[:company_id].present?
    @skill_markdown = read_skill_file("SKILL.md")
    @ai_prompt = build_ai_prompt
  end

  private

  def read_skill_file(filename)
    path = Rails.root.join(SKILL_DIR, filename)
    return "（找不到 #{SKILL_DIR}/#{filename}）" unless File.exist?(path)

    File.read(path)
  end

  def build_ai_prompt
    project_name = @selected_company&.name || "（請替換為母專案名稱）"
    github = [@selected_company&.github_owner, @selected_company&.name].compact.join("/")
    github_line = github.present? ? "Repository：`#{github}`" : "Repository：（匯入後的 GitHub owner/repo）"

    <<~PROMPT
      請依下列 Cursor Skill，為母專案 **#{project_name}** 補齊 zh-TW I18n（model.yml / actor.yml / controller.yml）。
      #{github_line}

      ## 分支約定（必做）
      1. 若尚無 `#{RECOMMENDED_BRANCH}` 分支，請建立並切換：`git checkout -b #{RECOMMENDED_BRANCH}`
      2. 所有 locale 修改只提交到 `#{RECOMMENDED_BRANCH}`。
      3. 完成後在 RelateDoc 對該專案「同步 GitHub 母資料」，分支填入：`#{RECOMMENDED_BRANCH}`。

      ## 用詞來源
      - 以該專案前端 navbar、Vue、ERB 實際顯示為準（勿直譯英文 class 名）
      - 逐項對照 UI／schema 補 yml

      ## Skill 全文
      #{@skill_markdown}
    PROMPT
  end
end
