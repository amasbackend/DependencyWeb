# frozen_string_literal: true

namespace :companies do
  desc "將 github_owner 為 NULL 或空字串的公司設為 AMASTek"
  task backfill_github_owner: :environment do
    scope = Company.where("github_owner IS NULL OR github_owner = ?", "")
    updated = scope.update_all(github_owner: "AMASTek")
    puts "已更新 #{updated} 筆 company 的 github_owner 為 AMASTek"
  end
end
