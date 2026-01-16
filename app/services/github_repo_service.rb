# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"

class GithubRepoService
  def initialize(access_token = nil)
    @access_token = access_token || ENV.fetch("GITHUB_ACCESS_TOKEN", nil)
    @base_url = "https://api.github.com"
    @api_version = "2022-11-28"
  end

  # 獲取指定路徑下的所有檔案（遞迴）
  def get_directory_files(owner, repo, path, branch = "main")
    files = []
    get_directory_contents(owner, repo, path, branch, files)
    files
  end

  # 獲取指定路徑下的子目錄列表（僅第一層）
  def get_subdirectories(owner, repo, path, branch = "main")
    uri = URI("#{@base_url}/repos/#{owner}/#{repo}/contents/#{path}")
    uri.query = URI.encode_www_form({ ref: branch }) if branch

    response = execute_request(uri)

    if response.code == "200"
      contents = JSON.parse(response.body)
      contents.select { |item| item["type"] == "dir" }.map { |item| item["name"] }
    else
      puts "⚠️  無法取得目錄列表 #{path}: #{response.code} - #{response.body}"
      []
    end
  rescue StandardError => e
    puts "⚠️  錯誤取得目錄列表 #{path}: #{e.message}"
    []
  end

  # 獲取單個檔案內容
  def get_file_content(owner, repo, path, branch = "main")
    uri = URI("#{@base_url}/repos/#{owner}/#{repo}/contents/#{path}")
    uri.query = URI.encode_www_form({ ref: branch }) if branch

    response = execute_request(uri)

    if response.code == "200"
      file_data = JSON.parse(response.body)
      if file_data["type"] == "file" && file_data["content"]
        {
          content: Base64.decode64(file_data["content"]),
          path: file_data["path"],
          sha: file_data["sha"],
        }
      elsif file_data["type"] == "dir"
        nil # 目錄，需要遞迴處理
      end
    else
      puts "⚠️  無法取得檔案 #{path}: #{response.code} - #{response.body}"
      nil
    end
  rescue StandardError => e
    puts "⚠️  錯誤取得檔案 #{path}: #{e.message}"
    nil
  end

  private

  # 遞迴獲取目錄內容
  def get_directory_contents(owner, repo, path, branch, files)
    uri = URI("#{@base_url}/repos/#{owner}/#{repo}/contents/#{path}")
    uri.query = URI.encode_www_form({ ref: branch }) if branch

    response = execute_request(uri)

    if response.code == "200"
      contents = JSON.parse(response.body)
      contents.each do |item|
        if item["type"] == "file"
          files << {
            path: item["path"],
            name: item["name"],
            size: item["size"],
          }
        elsif item["type"] == "dir"
          # 遞迴處理子目錄
          get_directory_contents(owner, repo, item["path"], branch, files)
        end
      end
    else
      puts "⚠️  無法取得目錄 #{path}: #{response.code} - #{response.body}"
    end
  rescue StandardError => e
    puts "⚠️  錯誤取得目錄 #{path}: #{e.message}"
  end

  def build_request(uri)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@access_token}" if @access_token
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = @api_version
    request["User-Agent"] = "Rails-App-GitHub-Analysis"
    request
  end

  def execute_request(uri)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(build_request(uri))
    end
  end
end
