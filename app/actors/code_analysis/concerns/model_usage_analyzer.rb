# frozen_string_literal: true

module CodeAnalysis
  module Concerns
    module ModelUsageAnalyzer
      extend ActiveSupport::Concern

      private

      # 分析 model 使用方式的輔助方法
      def analyze_model_usage(content, model_class)
        result = {
          select_column: [],
          modify_column: [],
          delete_column: [],
        }

        # 標準方法關鍵字分類
        select_methods = %w[find find_by where select all first last limit offset order group
                            having includes joins left_joins]
        modify_methods = %w[update update_all save save! create create! new build]
        delete_methods = %w[destroy destroy_all delete delete_all]

        # 尋找該 model 的所有方法調用
        lines = content.split("\n")
        lines.each_with_index do |line, index|
          analyze_single_method_call(line, model_class, select_methods, modify_methods, delete_methods, result)
          analyze_chain_method_call(line, model_class, select_methods, modify_methods, delete_methods, result)
          analyze_implicit_method_call(line, index, lines, model_class, select_methods, modify_methods, delete_methods,
                                       result)
        end

        # 去重並排序
        result.each do |key, value|
          result[key] = value.uniq.sort
        end

        result
      end

      def analyze_single_method_call(line, model_class, select_methods, modify_methods, delete_methods, result)
        method_pattern = /#{Regexp.escape(model_class)}\s*\.\s*(\w+)\s*\(([^)]*)\)/
        return unless (match = line.match(method_pattern))

        method_name = match[1]
        params = match[2].strip

        classify_method(method_name, params, select_methods, modify_methods, delete_methods, result)
      end

      def analyze_chain_method_call(line, model_class, select_methods, modify_methods, delete_methods, result)
        chain_pattern = /#{Regexp.escape(model_class)}\s*\.\s*(\w+)\s*\(([^)]*)\)\s*\.\s*(\w+)\s*\(([^)]*)\)/
        return unless (match = line.match(chain_pattern))

        first_method = match[1]
        first_params = match[2].strip
        second_method = match[3]
        second_params = match[4].strip

        classify_method(first_method, first_params, select_methods, modify_methods, delete_methods, result)
        classify_method(second_method, second_params, select_methods, modify_methods, delete_methods, result)
      end

      def analyze_implicit_method_call(line, index, lines, model_class, select_methods, modify_methods, delete_methods,
                                       result)
        return unless index.positive?

        all_methods = [select_methods, modify_methods, delete_methods].flatten.join("|")
        method_pattern = /\.\s*(#{all_methods})\s*\(([^)]*)\)/
        return unless line.match?(method_pattern)

        previous_line = lines[index - 1]
        model_pattern = /\w+\s*=\s*#{Regexp.escape(model_class)}/
        return unless previous_line.include?(model_class) || previous_line.match?(model_pattern)

        method_match = line.match(/\.\s*(\w+)\s*\(([^)]*)\)/)
        return unless method_match

        method_name = method_match[1]
        params = method_match[2].strip
        classify_method(method_name, params, select_methods, modify_methods, delete_methods, result)
      end

      def classify_method(method_name, params, select_methods, modify_methods, delete_methods, result)
        if select_methods.include?(method_name)
          result[:select_column].concat(extract_params(params))
        elsif modify_methods.include?(method_name)
          result[:modify_column].concat(extract_params(params))
        elsif delete_methods.include?(method_name)
          result[:delete_column].concat(extract_params(params))
        end
      end

      # 提取參數中的欄位名稱
      def extract_params(params_string)
        return [] if params_string.empty?

        params = []

        # 處理 Hash 格式的參數，例如 { id: 1, name: "test" }
        hash_pattern = /(\w+)\s*:\s*[^,}]+/
        params_string.scan(hash_pattern).each do |match|
          params << match[0]
        end

        # 處理字串參數，例如 "id", "name"
        string_pattern = /["']([^"']+)["']/
        params_string.scan(string_pattern).each do |match|
          params << match[0]
        end

        # 處理變數參數，例如 user_id, customer_id (只提取完整的變數名)
        var_pattern = /\b(\w+_id)\b/
        params_string.scan(var_pattern).each do |match|
          params << match[0]
        end

        # 處理直接欄位名稱，例如 id, name (避免與上面的重複)
        direct_pattern = /\b(id|name|email|created_at|updated_at)\b/
        params_string.scan(direct_pattern).each do |match|
          params << match[0] unless params.include?(match[0])
        end

        params
      end
    end
  end
end
