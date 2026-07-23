# frozen_string_literal: true

class I18nGuidesController < ApplicationController
  RECOMMENDED_BRANCH = "test/i18n"
  SKILL_DIR = ".cursor/skills/relatedoc-i18n"

  def show
    @recommended_branch = RECOMMENDED_BRANCH
    @skill_path = File.join(SKILL_DIR, "SKILL.md")
    @project_name = params[:project].to_s.strip
    @repository = params[:repo].to_s.strip
    @matched_company = find_matched_company
    @skill_markdown = read_skill_file("SKILL.md")
    @ai_prompt = build_ai_prompt
  end

  private

  def read_skill_file(filename)
    path = Rails.root.join(SKILL_DIR, filename)
    return "（找不到 #{SKILL_DIR}/#{filename}）" unless File.exist?(path)

    File.read(path)
  end

  def find_matched_company
    return nil if @project_name.blank?

    Company.find_by(name: @project_name)
  end

  def build_ai_prompt
    project_name = @project_name.presence || "（請替換為母專案名稱）"
    github_line =
      if @repository.present?
        "Repository：`#{@repository}`"
      else
        "Repository：（匯入後的 GitHub owner/repo）"
      end

    <<~PROMPT
      請依下列 Cursor Skill，在母專案 **#{project_name}** 的 repo 內補齊 zh-TW I18n。
      #{github_line}

      ## 目標
      - 只改該專案的 `config/locales/zh-TW/*.yml`
      - 用詞以該專案前端 navbar、Vue、ERB、schema 為準
      - 依 Skill 列出的路徑掃描 actors／permission_check／選單／欄位並補譯

      ## 分支約定（必做）
      1. 若尚無 `#{RECOMMENDED_BRANCH}`：`git checkout -b #{RECOMMENDED_BRANCH}`
      2. locale 修改只提交到 `#{RECOMMENDED_BRANCH}`
      3. 完成後 push，匯入端同步時分支填 `#{RECOMMENDED_BRANCH}`

      ## Skill 全文
      #{@skill_markdown}
    PROMPT
  end
end
