# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlagUpdateService do
  let(:company) { Company.create!(name: "PrjJieZhou", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Check",
      changed_flag: true,
      relate_model: ["WorkOrder"],
    )
  end
  let!(:relate_model) do
    RelateModel.create!(
      management_page: management_page,
      action_page: action_page,
      name: "WorkOrder",
      changed_flag: true,
    )
  end

  let(:github_double) { instance_double(GithubAnalysisService) }
  let(:impact_double) { instance_double(ImpactAnalysisService) }
  let(:report_double) { instance_double(TestScopeReportService) }

  let(:analysis_result) do
    {
      changed_files: ["app/actors/work_order/check.rb"],
      actor_changes: [{ actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" }],
      model_changes: [],
      controller_changes: [],
      migration_changes: [],
      concern_changes: [],
      blueprint_changes: [],
      classified_counts: { "actor" => 1 },
      column_impacts: [],
      route_changes: [],
    }
  end

  let(:summary) do
    {
      total_impacts: 2,
      action_pages_flagged: 1,
      relate_models_flagged: 1,
      by_level: { "direct" => 1, "caller" => 1 },
    }
  end

  subject(:service) do
    described_class.new.tap do |svc|
      svc.instance_variable_set(:@github_service, github_double)
      svc.instance_variable_set(:@impact_analysis_service, impact_double)
      svc.instance_variable_set(:@report_service, report_double)
    end
  end

  before do
    ImpactRecord.create!(
      company: company,
      pr_number: 65,
      source_type: "actor",
      source_name: "WorkOrder::Check",
      source_file_path: "app/actors/work_order/check.rb",
      target_type: "action_page",
      target_id: action_page.id,
      impact_level: "direct",
      reason: "test",
    )

    allow(github_double).to receive(:analyze_changes).and_return(analysis_result)
    allow(impact_double).to receive(:analyze_and_persist!).and_return(summary)
    allow(report_double).to receive(:generate).and_return({ must_test: [] })
  end

  describe "#update_flags_from_pr" do
    it "resets flags, analyzes PR, and persists summary" do
      result = service.update_flags_from_pr("AMASTek", "PrjJieZhou", 65, "PrjJieZhou")

      expect(result[:changed_files_count]).to eq(1)
      expect(PrAnalysis.for_pr(company.id, 65).count).to eq(1)
      expect(impact_double).to have_received(:analyze_and_persist!).with(
        hash_including(company: company, pr_number: 65),
      )
    end

    it "raises when company is missing" do
      expect do
        service.update_flags_from_pr("AMASTek", "PrjJieZhou", 65, "MissingCo")
      end.to raise_error(/找不到公司/)
    end
  end

  describe "#reset_all_flags" do
    it "clears changed flags and impact records" do
      service.reset_all_flags("PrjJieZhou")

      expect(action_page.reload.changed_flag).to be false
      expect(relate_model.reload.changed_flag).to be false
      expect(ImpactRecord.where(company: company)).to be_empty
    end

    it "returns early when company is missing" do
      expect { service.reset_all_flags("MissingCo") }.not_to raise_error
    end
  end

  describe "#show_flag_statistics" do
    it "prints statistics for changed records" do
      expect { service.show_flag_statistics("PrjJieZhou") }.to output(/變更的 ActionPage/).to_stdout
    end

    it "prints relate model details when present" do
      expect { service.show_flag_statistics("PrjJieZhou") }.to output(/變更的 RelateModel/).to_stdout
    end

    it "returns early when company is missing" do
      expect { service.show_flag_statistics("MissingCo") }.not_to output.to_stdout
    end
  end

  describe "snapshot persistence failures" do
    it "continues when PR snapshot persistence fails" do
      allow(report_double).to receive(:generate).and_raise(StandardError, "report failed")

      expect do
        service.update_flags_from_pr("AMASTek", "PrjJieZhou", 65, "PrjJieZhou")
      end.to output(/PR 分析快照儲存失敗/).to_stdout
    end
  end
end
