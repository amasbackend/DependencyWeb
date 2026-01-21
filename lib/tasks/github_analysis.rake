namespace :github_analysis do
  desc "分析 GitHub PR 檔案變更並更新 flag 標記"
  task :update_flags, %i[owner repo pr_number company_name] => :environment do |_t, args|
    # 設定預設值
    owner = args[:owner] || "AMASTek"
    repo = args[:repo] || "PrjJieZhou"
    pr_number = args[:pr_number] || "65"
    company_name = args[:company_name] || "PrjJieZhou"

    puts "開始分析 GitHub PR..."
    puts "Repository: #{owner}/#{repo}"
    puts "PR Number: #{pr_number}"
    puts "Company: #{company_name}"

    begin
      flag_service = FlagUpdateService.new
      flag_service.update_flags_from_pr(owner, repo, pr_number, company_name)
      flag_service.show_flag_statistics(company_name)

      puts "\n✅ GitHub PR 分析完成！"
    rescue StandardError => e
      puts "❌ 錯誤: #{e.message}"
      puts e.backtrace.first(5).join("\n")

      # 提供除錯建議
      puts "\n🔍 除錯建議："
      puts "1. 檢查 repository 是否存在: https://github.com/#{owner}/#{repo}"
      puts "2. 檢查 PR 是否存在: https://github.com/#{owner}/#{repo}/pull/#{pr_number}"
      puts "3. 確認 GitHub Access Token 已設定: GITHUB_ACCESS_TOKEN"
      puts "4. 嘗試列出可用的 PR: rails github_analysis:list_prs[#{owner},#{repo}]"
    end
  end

  desc "顯示目前 flag 狀態統計"
  task :show_stats, [:company_name] => :environment do |_t, args|
    company_name = args[:company_name] || "PrjJieZhou"

    begin
      flag_service = FlagUpdateService.new
      flag_service.show_flag_statistics(company_name)
    rescue StandardError => e
      puts "❌ 錯誤: #{e.message}"
    end
  end

  desc "重置所有 flag 狀態"
  task :reset_flags, [:company_name] => :environment do |_t, args|
    company_name = args[:company_name] || "PrjJieZhou"

    begin
      flag_service = FlagUpdateService.new
      flag_service.reset_all_flags(company_name)
      puts "✅ 所有 flag 已重置"
    rescue StandardError => e
      puts "❌ 錯誤: #{e.message}"
    end
  end

  desc "測試 GitHub API 連線"
  task :test_connection, %i[owner repo pr_number] => :environment do |_t, args|
    owner = args[:owner] || "AMASTek"
    repo = args[:repo] || "PrjJieZhou"
    pr_number = args[:pr_number] || "65"

    begin
      github_service = GithubAnalysisService.new

      # 先檢查 PR 是否存在
      puts "檢查 PR 是否存在..."
      pr_check = github_service.check_pr_exists(owner, repo, pr_number)

      if pr_check[:exists]
        puts "✅ PR 存在！"
        files = github_service.get_pr_files(owner, repo, pr_number)
        puts "PR #{pr_number} 包含 #{files.count} 個檔案變更"

        # 顯示前 10 個變更的檔案
        puts "\n前 10 個變更的檔案："
        files.first(10).each_with_index do |file, index|
          puts "  #{index + 1}. #{file['filename']} (#{file['status']})"
        end
      else
        puts "❌ PR 不存在或無法存取"
        puts "狀態碼: #{pr_check[:status_code]}"
        puts "回應內容: #{pr_check[:body]}"

        # 嘗試列出可用的 PR
        puts "\n嘗試列出可用的 PR..."
        list_available_prs(owner, repo)
      end
    rescue StandardError => e
      puts "❌ GitHub API 連線失敗: #{e.message}"
      puts "\n請檢查："
      puts "1. 網路連線是否正常"
      puts "2. GitHub Access Token 是否設定正確 (GITHUB_ACCESS_TOKEN)"
      puts "3. Repository 和 PR 編號是否正確"
    end
  end

  desc "列出可用的 PR"
  task :list_prs, %i[owner repo] => :environment do |_t, args|
    owner = args[:owner] || "AMASTek"
    repo = args[:repo] || "PrjJieZhou"

    begin
      list_available_prs(owner, repo)
    rescue StandardError => e
      puts "❌ 無法列出 PR: #{e.message}"
    end
  end

  private

  def list_available_prs(owner, repo)
    uri = URI("https://api.github.com/repos/#{owner}/#{repo}/pulls?state=all&per_page=10")

    request = Net::HTTP::Get.new(uri)
    # 使用新的認證方式
    request["Authorization"] = "Bearer #{GITHUB_ACCESS_TOKEN}" if GITHUB_ACCESS_TOKEN
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["User-Agent"] = "Rails-App-GitHub-Analysis"

    puts "🔍 檢查 Repository: #{uri}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    puts "📡 回應狀態: #{response.code}"

    if response.code == "200"
      prs = JSON.parse(response.body)
      puts "可用的 PR 列表："
      prs.each do |pr|
        puts "  ##{pr['number']}: #{pr['title']} (#{pr['state']})"
      end
    else
      puts "無法取得 PR 列表: #{response.code} - #{response.body}"
    end
  end
end
