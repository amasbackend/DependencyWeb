# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestScopeReportService do
  subject(:service) { described_class.new }

  let(:company) { Company.create!(name: "BranchCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

  it "skips duplicate action page impacts" do
    action_page = ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Update",
      operation_type: "編輯",
      relate_model: ["WorkOrder"],
      select_column: %w[name],
    )

    2.times do
      ImpactRecord.create!(
        company: company,
        pr_number: 90,
        source_type: "actor",
        source_name: "WorkOrder::Update",
        source_file_path: "app/actors/work_order/update.rb",
        target_type: "action_page",
        target_id: action_page.id,
        impact_level: "direct",
        reason: "duplicate",
      )
    end

    report = service.generate(company: company, pr_number: 90, format: "qa")

    expect(report[:must_test].size).to eq(1)
    expect(report[:must_test].first[:affected_fields]).to eq(["name"])
  end

  it "returns unknown target names for unsupported impact types" do
    impact = instance_double(
      ImpactRecord,
      target_type: "unknown",
      target_id: 1,
      source_type: "actor",
      source_name: "WorkOrder::List",
      source_file_path: "app/actors/work_order/list.rb",
      impact_level: "caller",
      reason: "misc",
    )
    allow(ImpactRecord).to receive(:for_pr).and_return([impact])

    report = service.generate(company: company, pr_number: 91, format: "tech")

    expect(report[:impacts].first[:target_name]).to be_nil
  end

  it "omits uncovered risks when analysis input is blank" do
    action_page = ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::List",
      operation_type: "查詢",
    )
    ImpactRecord.create!(
      company: company,
      pr_number: 92,
      source_type: "actor",
      source_name: "WorkOrder::List",
      source_file_path: "app/actors/work_order/list.rb",
      target_type: "action_page",
      target_id: action_page.id,
      impact_level: "caller",
      reason: "caller",
    )

    report = service.generate(company: company, pr_number: 92, format: "qa")

    expect(report[:suggested_regression].size).to eq(1)
    expect(report[:uncovered_risks]).to eq([])
  end
end
