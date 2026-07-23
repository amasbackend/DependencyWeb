# frozen_string_literal: true

require "rails_helper"

RSpec.describe OperationTypeInfererService do
  it "maps common actor suffixes to Chinese labels" do
    expect(described_class.infer("WorkOrder::Create")).to eq("新增")
    expect(described_class.infer("ExamineRecord::Update")).to eq("編輯")
    expect(described_class.infer("WorkOrder::List")).to eq("列表")
    expect(described_class.infer("CncMachine::Find")).to eq("檢視")
    expect(described_class.infer("EstimateOrder::Finalize")).to eq("定稿")
    expect(described_class.infer("EstimateOrder::Sold")).to eq("成交")
    expect(described_class.infer("ExamineRecord::Archive")).to eq("封存")
    expect(described_class.infer("Custom::SpecialAction")).to eq("SpecialAction")
  end

  it "prefers locale operation_type labels when provided" do
    labels = { "per_produce_time" => "單件生產秒數", "ai_predict" => "AI預測" }

    expect(described_class.infer("CncMachine::PerProduceTime", labels: labels)).to eq("單件生產秒數")
    expect(described_class.infer("Component::AiPredict", labels: labels)).to eq("AI預測")
  end

  it "returns operation key" do
    expect(described_class.new.operation_key("WorkOrder::Create")).to eq("create")
    expect(described_class.new.operation_key("")).to be_nil
  end
end
