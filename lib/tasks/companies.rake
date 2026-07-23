# frozen_string_literal: true

namespace :companies do
  desc "將 github_owner 為 NULL 或空字串的公司設為 AMASTek"
  task backfill_github_owner: :environment do
    scope = Company.where("github_owner IS NULL OR github_owner = ?", "")
    updated = scope.update_all(github_owner: "AMASTek")
    puts "已更新 #{updated} 筆 company 的 github_owner 為 AMASTek"
  end

  desc "從 GitHub 同步指定專案的母資料（預設 master 分支）"
  task :sync, %i[company_name branch] => :environment do |_t, args|
    company_name = args[:company_name] || ENV.fetch("company", nil)
    branch = args[:branch] || ENV.fetch("BRANCH", "master")

    unless company_name
      puts "❌ 請指定公司名稱，例如: rails companies:sync[PrjJieZhou]"
      puts "   或: company=PrjJieZhou BRANCH=master rails companies:sync"
      next
    end

    company = Company.find_by(name: company_name)
    unless company
      puts "❌ 找不到公司: #{company_name}"
      next
    end

    puts "開始同步 #{company.github_owner.presence || 'AMASTek'}/#{company.name} (分支: #{branch})..."

    result = CodeAnalysis::SyncFromGithub.result(company_id: company.id, branch: branch)

    if result.success?
      stats = result.statistics
      puts "✅ #{result.message}"
      puts "   管理頁面: #{stats[:management_pages_count]}"
      puts "   Action Page: #{stats[:action_pages_count]}"
      puts "   Relate Model: #{stats[:relate_models_count]}"
      puts "   同步時間: #{result.company.last_synced_at}"
    else
      puts "❌ #{result.error}"
      exit 1
    end
  end
end
