# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImpactAnalysisService do
  subject(:service) { described_class.new }

  let(:company) { Company.create!(name: "TestCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

  let!(:check_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Check",
      relate_action: [],
      relate_model: ["WorkOrder"],
    )
  end

  let!(:create_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Create",
      relate_action: ["WorkOrder::Check"],
      relate_model: ["WorkOrder", "Component"],
    )
  end

  let!(:approve_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Approve",
      relate_action: ["WorkOrder::Create"],
      relate_model: [],
    )
  end

  let!(:check_relate_model) do
    RelateModel.create!(
      management_page: management_page,
      action_page: check_page,
      name: "WorkOrder",
    )
  end

  let!(:component_relate_model) do
    RelateModel.create!(
      management_page: management_page,
      action_page: create_page,
      name: "Component",
    )
  end

  describe "#analyze" do
    it "marks direct actor, callers, and callee models" do
      impacts = service.analyze(
        company: company,
        pr_number: 65,
        actor_changes: [
          { actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" },
        ],
        model_changes: [],
      )

      action_impacts = impacts.select { |i| i[:target_type] == "action_page" }
      levels = action_impacts.pluck(:impact_level)

      expect(levels).to include("direct", "caller")
      expect(impacts.any? { |i| i[:target_type] == "relate_model" && i[:impact_level] == "callee" }).to be true
    end

    it "marks second-level callers" do
      impacts = service.analyze(
        company: company,
        pr_number: 65,
        actor_changes: [
          { actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" },
        ],
        model_changes: [],
      )

      approve_impact = impacts.find { |i| i[:target_id] == approve_page.id }
      expect(approve_impact[:impact_level]).to eq("caller_l2")
    end

    it "marks model consumers and direct relate models" do
      impacts = service.analyze(
        company: company,
        pr_number: 65,
        actor_changes: [],
        model_changes: [
          { model_name: "Component", file_path: "app/models/component.rb" },
        ],
      )

      expect(impacts.any? { |i| i[:impact_level] == "model_consumer" && i[:target_id] == create_page.id }).to be true
      expect(impacts.any? { |i| i[:target_type] == "relate_model" && i[:target_id] == component_relate_model.id }).to be true
    end

    it "keeps direct priority over caller for the same target" do
      impacts = service.analyze(
        company: company,
        pr_number: 65,
        actor_changes: [
          { actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" },
        ],
        model_changes: [],
      )

      check_impact = impacts.find { |i| i[:target_type] == "action_page" && i[:target_id] == check_page.id }
      expect(check_impact[:impact_level]).to eq("direct")
    end

    it "marks action pages and entry points linked via controller changes" do
      entry_point = EntryPoint.create!(
        company: company,
        action_page: check_page,
        controller_path: "pms/work_orders",
        controller_action: "update",
      )

      impacts = service.analyze(
        company: company,
        pr_number: 70,
        actor_changes: [],
        model_changes: [],
        controller_changes: [
          { controller_path: "pms/work_orders", file_path: "app/controllers/pms/work_orders_controller.rb" },
        ],
      )

      expect(impacts.any? { |i| i[:target_type] == "action_page" && i[:target_id] == check_page.id }).to be true
      expect(impacts.any? { |i| i[:target_type] == "entry_point" && i[:target_id] == entry_point.id }).to be true
    end

    it "marks actors that include a changed concern" do
      update_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "ExamineRecord::Update",
        relate_action: [],
        relate_model: ["ExamineRecord"],
      )
      SharedConcern.create!(
        company: company,
        action_page: update_page,
        concern_name: "ExamineRecordParamBuilding",
        concern_file_path: "app/actors/concerns/examine_record_param_building.rb",
      )

      impacts = service.analyze(
        company: company,
        pr_number: 71,
        actor_changes: [],
        model_changes: [],
        concern_changes: [
          {
            concern_name: "ExamineRecordParamBuilding",
            file_path: "app/actors/concerns/examine_record_param_building.rb",
          },
        ],
      )

      impact = impacts.find { |i| i[:target_id] == update_page.id }
      expect(impact[:impact_level]).to eq("concern")
    end

    it "marks actors that reference a changed blueprint" do
      blueprint_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Show",
        blueprint_names: ["WorkOrder::InfoBlueprint"],
      )

      impacts = service.analyze(
        company: company,
        pr_number: 72,
        actor_changes: [],
        model_changes: [],
        blueprint_changes: [
          {
            blueprint_name: "WorkOrder::InfoBlueprint",
            file_path: "app/blueprints/work_order/info_blueprint.rb",
          },
        ],
      )

      impact = impacts.find { |i| i[:target_id] == blueprint_page.id }
      expect(impact[:impact_level]).to eq("model_consumer")
    end

    it "marks migration column impacts on referenced columns" do
      create_page.update!(modify_column: %w[estimated_hours])

      impacts = service.analyze(
        company: company,
        pr_number: 73,
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

      expect(impacts.any? { |i| i[:target_id] == create_page.id && i[:impact_level] == "model_consumer" }).to be true
      expect(impacts.any? { |i| i[:target_type] == "relate_model" && i[:target_id] == check_relate_model.id }).to be true
    end

    it "ignores unknown actor names without raising" do
      impacts = service.analyze(
        company: company,
        pr_number: 74,
        actor_changes: [
          { actor_name: "Missing::Actor", file_path: "app/actors/missing/actor.rb" },
        ],
        model_changes: [],
      )

      expect(impacts).to be_empty
    end

    it "skips migration impacts when columns are not referenced" do
      impacts = service.analyze(
        company: company,
        pr_number: 75,
        actor_changes: [],
        model_changes: [],
        migration_changes: [
          {
            file_path: "db/migrate/20260101000000_add_hours.rb",
            column_impacts: [
              {
                table: "work_orders",
                column: "unused_column",
                change_type: "add_column",
                model_name: "WorkOrder",
              },
            ],
          },
        ],
      )

      expect(impacts.select { |i| i[:target_id] == create_page.id }).to be_empty
    end

    it "keeps higher priority impact when merging duplicates" do
      impacts = service.analyze(
        company: company,
        pr_number: 76,
        actor_changes: [
          { actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" },
        ],
        model_changes: [
          { model_name: "WorkOrder", file_path: "app/models/work_order.rb" },
        ],
      )

      check_impact = impacts.find { |i| i[:target_type] == "action_page" && i[:target_id] == check_page.id }
      expect(check_impact[:impact_level]).to eq("direct")
    end
  end

  describe "#analyze_and_persist!" do
    it "writes impact records and syncs changed flags" do
      summary = service.analyze_and_persist!(
        company: company,
        pr_number: 65,
        actor_changes: [
          { actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" },
        ],
        model_changes: [],
      )

      expect(ImpactRecord.where(company: company, pr_number: 65).count).to be_positive
      expect(check_page.reload.changed_flag).to be true
      expect(create_page.reload.changed_flag).to be true
      expect(summary[:total_impacts]).to be_positive
      expect(summary[:direct_actors]).to eq(["WorkOrder::Check"])
    end
  end
end
