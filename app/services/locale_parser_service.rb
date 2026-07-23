# frozen_string_literal: true

require "yaml"

class LocaleParserService
  def parse(yaml_content)
    data = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true) || {}
    locale_root = data["zh-TW"] || data[:zh_TW] || data

    {
      model_labels: deep_stringify(locale_root.dig("activerecord", "models") || {}),
      attribute_labels: deep_stringify(locale_root.dig("activerecord", "attributes") || {}),
      perm_module_labels: deep_stringify(locale_root["perm_module"] || {}),
      perm_action_labels: deep_stringify(locale_root["perm_action"] || {}),
      operation_type_labels: deep_stringify(locale_root["operation_type"] || {}),
      menu_labels: deep_stringify(locale_root["menu"] || {}),
      state_labels: deep_stringify(locale_root["state"] || {}),
    }
  rescue Psych::SyntaxError => e
    puts "⚠️  Locale YAML 解析失敗: #{e.message}"
    empty_result
  end

  private

  def empty_result
    {
      model_labels: {},
      attribute_labels: {},
      perm_module_labels: {},
      perm_action_labels: {},
      operation_type_labels: {},
      menu_labels: {},
      state_labels: {},
    }
  end

  def deep_stringify(value)
    case value
    when Hash
      value.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
    else
      value
    end
  end
end
