# frozen_string_literal: true

require "rails_helper"

RSpec.describe LocaleParserService do
  subject(:service) { described_class.new }

  let(:yaml_content) do
    <<~YAML
      zh-TW:
        activerecord:
          models:
            work_order: "工單"
          attributes:
            work_order:
              cnc_machine_id: "設備名稱"
        perm_module:
          work_order: "生產管理"
        perm_action:
          edit: "編輯"
          delete: "刪除"
        operation_type:
          sold: "成交"
          per_produce_time: "單件生產秒數"
        menu:
          work_order: "工單管理"
        state:
          work_order:
            pending: "待處理"
    YAML
  end

  it "parses model, attribute, permission, and operation labels" do
    result = service.parse(yaml_content)

    expect(result[:model_labels]["work_order"]).to eq("工單")
    expect(result[:attribute_labels]["work_order"]["cnc_machine_id"]).to eq("設備名稱")
    expect(result[:perm_module_labels]["work_order"]).to eq("生產管理")
    expect(result[:perm_action_labels]["edit"]).to eq("編輯")
    expect(result[:perm_action_labels]["delete"]).to eq("刪除")
    expect(result[:operation_type_labels]["sold"]).to eq("成交")
    expect(result[:operation_type_labels]["per_produce_time"]).to eq("單件生產秒數")
    expect(result[:menu_labels]["work_order"]).to eq("工單管理")
    expect(result[:state_labels]["work_order"]["pending"]).to eq("待處理")
  end

  it "returns empty result for invalid YAML" do
    result = service.parse("invalid: [unclosed")

    expect(result).to eq(
      model_labels: {},
      attribute_labels: {},
      perm_module_labels: {},
      perm_action_labels: {},
      operation_type_labels: {},
      menu_labels: {},
      state_labels: {},
    )
  end
end
