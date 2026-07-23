# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImpactAnalysisService do
  subject(:service) { described_class.new }

  let(:company) { Company.create!(name: "BranchCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

  describe "branch coverage helpers" do
    let!(:action_page) do
      ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Check",
        relate_action: [],
        relate_model: ["WorkOrder"],
      )
    end

    it "handles entry points without linked action pages" do
      entry_point = EntryPoint.create!(
        company: company,
        action_page: nil,
        controller_path: "pms/work_orders",
        controller_action: "index",
      )

      impacts = service.analyze(
        company: company,
        pr_number: 80,
        actor_changes: [],
        model_changes: [],
        controller_changes: [
          { controller_path: "pms/work_orders", file_path: "app/controllers/pms/work_orders_controller.rb" },
        ],
      )

      expect(impacts.map { |i| i[:target_type] }).to eq(["entry_point"])
      expect(impacts.first[:target_id]).to eq(entry_point.id)
    end

    it "skips shared concerns without action pages" do
      shared = instance_double(SharedConcern, action_page: nil)
      relation = instance_double(ActiveRecord::Relation)
      allow(SharedConcern).to receive(:where).and_return(relation)
      allow(relation).to receive(:includes).with(:action_page).and_return(relation)
      allow(relation).to receive(:find_each).and_yield(shared)

      impacts = service.analyze(
        company: company,
        pr_number: 81,
        actor_changes: [],
        model_changes: [],
        concern_changes: [
          { concern_name: "OrphanConcern", file_path: "app/actors/concerns/orphan_concern.rb" },
        ],
      )

      expect(impacts).to be_empty
    end

    it "supports hash payloads in summary helpers" do
      impacts_hash = {
        ["action_page", action_page.id] => {
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "direct",
        },
      }

      summary = service.send(:build_summary, impacts_hash, [], [])
      service.send(:sync_changed_flags!, impacts_hash)

      expect(summary[:total_impacts]).to eq(1)
      expect(action_page.reload.changed_flag).to be true
    end

    it "syncs relate model flags without action pages" do
      relate_model = RelateModel.create!(
        management_page: management_page,
        action_page: action_page,
        name: "WorkOrder",
      )

      service.send(
        :sync_changed_flags!,
        [{ target_type: "relate_model", target_id: relate_model.id, impact_level: "direct" }],
      )

      expect(relate_model.reload.changed_flag).to be true
    end

    it "matches underscored column names in migration analysis" do
      action_page.update!(modify_column: %w[estimated_hours])

      impacts = service.analyze(
        company: company,
        pr_number: 82,
        actor_changes: [],
        model_changes: [],
        migration_changes: [
          {
            file_path: "db/migrate/20260101000000_add_hours.rb",
            column_impacts: [
              {
                table: "work_orders",
                column: "estimated_hours",
                change_type: "add_column",
                model_name: "WorkOrder",
              },
            ],
          },
        ],
      )

      expect(impacts.any? { |i| i[:target_id] == action_page.id }).to be true
    end

    it "keeps lower priority impacts when a stronger one already exists" do
      service.send(
        :merge_impact!,
        impacts = {},
        service.send(
          :build_impact,
          source: { source_type: "actor", source_name: "A", source_file_path: "a.rb" },
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "direct",
          reason: "direct",
        ),
      )
      service.send(
        :merge_impact!,
        impacts,
        service.send(
          :build_impact,
          source: { source_type: "actor", source_name: "B", source_file_path: "b.rb" },
          target_type: "action_page",
          target_id: action_page.id,
          impact_level: "caller",
          reason: "caller",
        ),
      )

      expect(impacts.values.first[:impact_level]).to eq("direct")
    end
  end
end
