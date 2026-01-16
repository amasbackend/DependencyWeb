# frozen_string_literal: true

module CodeAnalysis
  class AnalyzeManagementPagesFromGithub < Actor
    input :owner
    input :repo
    input :branch, default: "main"
    input :all_action_classes
    input :all_model_classes

    output :analysis_results

    def call
      self.analysis_results = {
        management_pages: {},
      }

      github_service = GithubRepoService.new

      # 獲取 app/actors 目錄下的第一層子目錄（管理頁面）
      management_page_dirs = github_service.get_subdirectories(owner, repo, "app/actors", branch)
                                           .reject { |name| name == "concerns" } # 排除 concerns 目錄

      management_page_dirs.each do |management_page_name|
        puts "\n管理頁面：#{management_page_name}"

        analysis_results[:management_pages][management_page_name] = {
          action_pages: {},
        }

        analyze_action_pages(owner, repo, branch, management_page_name, github_service)
      end
    end

    private

    def analyze_action_pages(owner, repo, branch, management_page_name, github_service)
      # 獲取該管理頁面目錄下的所有 .rb 檔案
      action_files = github_service.get_directory_files(owner, repo, "app/actors/#{management_page_name}", branch)
                                   .select { |f| f[:path].end_with?(".rb") }

      action_files.each do |file_info|
        file_content = github_service.get_file_content(owner, repo, file_info[:path], branch)
        next unless file_content

        content = file_content[:content]
        action_class_name = content[/class\s+([\w:]+)/, 1]

        next unless action_class_name

        puts "  動作頁面：#{action_class_name}"

        result = CodeAnalysis::AnalyzeActionPage.result(
          action_file: file_info[:path], # 傳入路徑而不是檔案物件
          action_class_name: action_class_name,
          content: content,
          all_action_classes: all_action_classes,
          all_model_classes: all_model_classes,
          management_page_name: management_page_name,
        )

        next unless result.success?

        action_page_info = result.action_page_info
        analysis_results[:management_pages][management_page_name][:action_pages][action_class_name] = action_page_info

        display_analysis_results(action_class_name, action_page_info)
      end
    end

    def display_analysis_results(action_class_name, action_page_info)
      return unless action_class_name && action_page_info

      puts "    關聯動作：#{action_page_info[:relate_actions].join(', ')}" if action_page_info[:relate_actions].any?

      if action_page_info[:relate_models].any?
        puts "    關聯模型：#{action_page_info[:relate_models].keys.join(', ')}"
        action_page_info[:relate_models].each do |model_class, model_info|
          puts "      #{model_class}: #{model_info}"
        end
      else
        puts "    （查無關聯模型）"
      end
    end
  end
end
