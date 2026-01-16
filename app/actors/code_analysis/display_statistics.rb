# frozen_string_literal: true

module CodeAnalysis
  class DisplayStatistics < Actor
    input :analysis_results

    output :statistics_summary

    def call
      self.statistics_summary = calculate_statistics

      display_statistics
      display_management_pages_structure
    end

    private

    def calculate_statistics
      {
        management_pages: analysis_results[:management_pages].count,
        action_pages: calculate_action_pages_count,
        relate_actions: calculate_relate_actions_count,
        relate_models: calculate_relate_models_count,
      }
    end

    def calculate_action_pages_count
      analysis_results[:management_pages].values.sum { |mp| mp[:action_pages].count }
    end

    def calculate_relate_actions_count
      analysis_results[:management_pages].values.sum do |mp|
        mp[:action_pages].values.sum { |ap| ap[:relate_actions].count }
      end
    end

    def calculate_relate_models_count
      analysis_results[:management_pages].values.sum do |mp|
        mp[:action_pages].values.sum { |ap| ap[:relate_models].count }
      end
    end

    def display_statistics
      puts "\n分析完成，統計資訊："
      puts "  管理頁面: #{statistics_summary[:management_pages]} 個"
      puts "  動作頁面: #{statistics_summary[:action_pages]}"
      puts "  關聯動作: #{statistics_summary[:relate_actions]}"
      puts "  關聯模型: #{statistics_summary[:relate_models]}"
    end

    def display_management_pages_structure
      puts "\n【管理頁面 (Management Pages)】"
      analysis_results[:management_pages].each_with_index do |(management_page_name, management_page_data), index|
        puts "  #{index + 1}. #{management_page_name}"
        puts "   動作頁面: #{management_page_data[:action_pages].count} 個"
      end
    end
  end
end
