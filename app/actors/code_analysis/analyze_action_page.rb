# frozen_string_literal: true

require "pathname"

module CodeAnalysis
  class AnalyzeActionPage < Actor
    include CodeAnalysis::Concerns::ModelUsageAnalyzer

    input :action_file
    input :action_class_name
    input :content
    input :all_action_classes
    input :all_model_classes
    input :management_page_name

    output :action_page_info

    def call
      self.action_page_info = {
        relate_actions: [],
        relate_models: {},
        select_column: [],
        modify_column: [],
        delete_column: [],
      }

      analyze_relate_actions
      analyze_relate_models
      deduplicate_columns
    end

    private

    def analyze_relate_actions
      used_action_classes = all_action_classes.select do |class_name|
        next if class_name == action_class_name

        pattern = /(?<![A-Za-z0-9_:])#{Regexp.escape(class_name)}(?![A-Za-z0-9_:])/
        content.match?(pattern)
      end

      action_page_info[:relate_actions] = used_action_classes if used_action_classes.any?
    end

    def analyze_relate_models
      used_model_classes = all_model_classes.select do |model_class|
        content.include?(model_class)
      end

      return unless used_model_classes.any?

      used_model_classes.each do |model_class|
        model_info = analyze_model_usage(content, model_class)
        action_page_info[:relate_models][model_class] = model_info

        action_page_info[:select_column].concat(model_info[:select_column])
        action_page_info[:modify_column].concat(model_info[:modify_column])
        action_page_info[:delete_column].concat(model_info[:delete_column])
      end
    end

    def deduplicate_columns
      action_page_info[:select_column] = action_page_info[:select_column].uniq.sort
      action_page_info[:modify_column] = action_page_info[:modify_column].uniq.sort
      action_page_info[:delete_column] = action_page_info[:delete_column].uniq.sort
    end
  end
end
