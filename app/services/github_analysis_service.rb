# frozen_string_literal: true

class GithubAnalysisService
  require "net/http"
  require "json"
  require "uri"
  require "base64"

  def initialize(access_token = nil)
    @access_token = access_token || GITHUB_ACCESS_TOKEN
    @base_url = "https://api.github.com"
    @api_version = "2022-11-28" # 使用穩定的 API 版本
  end

  # 檢查 PR 是否存在
  def check_pr_exists(owner, repo, pr_number)
    uri = URI("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}")
    
    request = Net::HTTP::Get.new(uri)
    # 使用新的認證方式
    request["Authorization"] = "Bearer #{@access_token}" if @access_token
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = @api_version
    request["User-Agent"] = "Rails-App-GitHub-Analysis"

    puts "🔍 檢查 PR: #{uri}"
    puts "🔑 使用 Token: #{@access_token ? '是' : '否'}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    puts "📡 回應狀態: #{response.code}"
    puts "📄 回應內容: #{response.body[0..200]}..." if response.body.length > 200

    {
      exists: response.code == "200",
      status_code: response.code,
      body: response.body,
    }
  end

  # 取得 PR 的檔案變更列表
  def get_pr_files(owner, repo, pr_number)
    uri = URI("#{@base_url}/repos/#{owner}/#{repo}/pulls/#{pr_number}/files")

    request = Net::HTTP::Get.new(uri)
    # 使用新的認證方式
    request["Authorization"] = "Bearer #{@access_token}" if @access_token
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = @api_version
    request["User-Agent"] = "Rails-App-GitHub-Analysis"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.code == "200"
      JSON.parse(response.body)
    else
      error_message = "GitHub API 錯誤: #{response.code} - #{response.body}"
      puts "API URL: #{uri}"
      puts "Response Code: #{response.code}"
      puts "Response Body: #{response.body}"
      raise error_message
    end
  end

  # 分析檔案變更並比對 actors 和 models
  def analyze_changes(owner, repo, pr_number)
    # 先檢查 PR 是否存在
    pr_check = check_pr_exists(owner, repo, pr_number)
    raise "PR 不存在或無法存取: #{owner}/#{repo} PR ##{pr_number} (狀態碼: #{pr_check[:status_code]})" unless pr_check[:exists]

    files = get_pr_files(owner, repo, pr_number)

    # 提取變更的檔案路徑
    changed_files = files.map { |file| file["filename"] }

    # 分析 actors 變更（傳入 owner 和 repo 以便取得檔案內容）
    actor_changes = analyze_actor_changes(changed_files, owner, repo)

    # 分析 model 變更
    model_changes = analyze_model_changes(changed_files)

    {
      changed_files: changed_files,
      actor_changes: actor_changes,
      model_changes: model_changes,
    }
  end

  private

  # 分析 actors 變更
  def analyze_actor_changes(changed_files, owner, repo)
    actor_changes = []

    changed_files.each do |file_path|
      # 檢查是否為 actors 目錄下的檔案，但排除 concerns 目錄（通常是 module，不是 actor）
      next unless file_path.match?(%r{^app/actors/.*\.rb$}) && !file_path.match?(%r{^app/actors/concerns/})

      # 嘗試從 GitHub API 取得檔案內容來解析 class name
      class_name = extract_class_name_from_github_file(file_path, owner, repo)

      if class_name
        actor_changes << {
          actor_name: class_name,
          file_path: file_path,
          change_type: determine_change_type(file_path),
        }
      elsif (match = file_path.match(%r{^app/actors/.*/([^/]+)\.rb$}))
        # 如果無法取得檔案內容，則從檔案路徑推斷
        actor_name = match[1]
        if actor_name
          actor_changes << {
            actor_name: actor_name,
            file_path: file_path,
            change_type: determine_change_type(file_path),
          }
        end
      end
    end

    actor_changes
  end

  # 分析 model 變更
  def analyze_model_changes(changed_files)
    model_changes = []

    changed_files.each do |file_path|
      # 檢查是否為 models 目錄下的檔案
      next unless (match = file_path.match(%r{^app/models/([^/]+)\.rb$}))

      model_name = match[1]&.camelize
      next unless model_name

      model_changes << {
        model_name: model_name,
        file_path: file_path,
        change_type: determine_change_type(file_path),
      }
    end

    model_changes
  end

  # 從 GitHub 檔案內容中提取 class name
  def extract_class_name_from_github_file(file_path, owner, repo)
    begin
      # 使用 GitHub API 取得檔案內容
      uri = URI("#{@base_url}/repos/#{owner}/#{repo}/contents/#{file_path}")

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@access_token}" if @access_token
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = @api_version
      request["User-Agent"] = "Rails-App-GitHub-Analysis"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == "200"
        file_data = JSON.parse(response.body)
        if file_data["content"]
          # 解碼 base64 內容
          content = Base64.decode64(file_data["content"])

          # 顯示檔案內容的前幾行用於除錯
          puts "📄 檔案 #{file_path} 內容預覽:"
          content.lines.first(5).each_with_index do |line, index|
            puts "  #{index + 1}: #{line.chomp}"
          end

          # 使用正規表達式提取 class name（包含命名空間）
          # 優先匹配帶有繼承的 class 定義（如 class BorrowingOrder::Check < Actor）
          if (match = content.match(/class\s+([A-Za-z][A-Za-z0-9_:]*)\s*</))
            class_name = match[1]
            puts "🔍 從檔案 #{file_path} 提取到 class name: #{class_name}"
            return class_name
          # 匹配一般的 class 定義（如 class BorrowingOrder::Check）
          elsif (match = content.match(/class\s+([A-Za-z][A-Za-z0-9_:]*)/))
            class_name = match[1]
            puts "🔍 從檔案 #{file_path} 提取到 class name: #{class_name}"
            return class_name
          elsif (match = content.match(/module\s+([A-Za-z][A-Za-z0-9_:]*)/))
            # 如果沒有找到 class，嘗試匹配 module（但通常不會用於 actor）
            module_name = match[1]
            puts "⚠️  檔案 #{file_path} 定義的是 module (#{module_name})，不是 class，已跳過"
          else
            puts "⚠️  無法從檔案 #{file_path} 中提取 class name"
            # 輸出更多除錯資訊
            puts "   檔案前 10 行內容："
            content.lines.first(10).each_with_index do |line, index|
              puts "     #{index + 1}: #{line.chomp}"
            end
          end
        end
      end
    rescue StandardError => e
      puts "⚠️  無法取得檔案內容 #{file_path}: #{e.message}"
    end

    # 如果無法取得檔案內容或提取失敗，則從檔案路徑推斷（這是最後的手段）
    # 但這只能得到檔案名稱，不是完整的 class name
    if (match = file_path.match(%r{^app/actors/.*/([^/]+)\.rb$}))
      file_name = match[1]
      puts "⚠️  無法從檔案內容提取 class name，使用檔案名稱: #{file_name}（可能不準確）"
      return file_name
    end
    nil
  end

  # 判斷變更類型
  def determine_change_type(_file_path)
    # 這裡可以根據檔案狀態判斷變更類型
    # 在 GitHub API 中，file['status'] 會提供 'added', 'modified', 'removed' 等狀態
    "modified" # 預設為修改
  end
end
