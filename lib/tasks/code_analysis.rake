# frozen_string_literal: true

namespace :code_analysis do
  desc "從 GitHub 分析專案，輸出關聯類別與方法"
  task relations: :environment do
    owner = ENV["OWNER"] || "AMASTek"
    repos = ENV["REPOS"]&.split(",") || %w[PrjNO PrjJieZhou HRM-BE PrjAGWms PrjAGFlow]
    branch = ENV["BRANCH"] || "main"

    repos.each do |repo|
      puts "開始分析程式碼..."
      puts "Repository: #{owner}/#{repo}"
      puts "Branch: #{branch}"

      result = CodeAnalysis::RelationsFromGithub.result(
        project_name: repo,
        owner: owner,
        repo: repo,
        branch: branch,
      )

      if result.success?
        puts "\n✅ 程式碼分析完成！"
      else
        puts "\n❌ 錯誤: #{result.error}"
      end
    end
  end
end
