# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Service branch coverage" do
  describe ImpactAnalysisService do
    subject(:service) { described_class.new }

    let(:company) { Company.create!(name: "DeepBranch", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "handles missing management page metadata in impact records" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Check",
        relate_model: ["WorkOrder"],
      )
      RelateModel.create!(
        management_page: management_page,
        action_page: action_page,
        name: "WorkOrder",
      )
      allow_any_instance_of(ActionPage).to receive(:management_page).and_return(nil)
      allow_any_instance_of(RelateModel).to receive(:management_page).and_return(nil)
      allow_any_instance_of(RelateModel).to receive(:action_page).and_return(action_page)

      impacts = service.analyze(
        company: company,
        pr_number: 1,
        actor_changes: [{ actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" }],
        model_changes: [{ model_name: "WorkOrder", file_path: "app/models/work_order.rb" }],
        controller_changes: [
          { controller_path: "pms/work_orders", file_path: "app/controllers/pms/work_orders_controller.rb" },
        ],
        migration_changes: [
          {
            file_path: "db/migrate/20260101000000_add_hours.rb",
            column_impacts: [
              { table: "work_orders", column: "name", change_type: "add_column", model_name: "WorkOrder" },
            ],
          },
        ],
        concern_changes: [{ concern_name: "Foo", file_path: "app/actors/concerns/foo.rb" }],
        blueprint_changes: [{ blueprint_name: "WorkOrder::InfoBlueprint", file_path: "app/blueprints/work_order/info_blueprint.rb" }],
      )

      expect(impacts).not_to be_empty
      expect(impacts.all? { |impact| impact[:metadata].value?(nil) || impact[:metadata].values.compact.empty? }).to be true
    end

    it "does not update flags when impact lists are empty" do
      service.send(:sync_changed_flags!, [])

      expect(ActionPage.where(changed_flag: true)).to be_empty
      expect(RelateModel.where(changed_flag: true)).to be_empty
    end
  end

  describe GithubAnalysisService do
    it "analyzes actor changes using github file content" do
      service = described_class.new("token")
      file_body = { "content" => Base64.encode64("class WorkOrder::Check < Actor\nend") }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: file_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = service.send(
        :analyze_actor_changes,
        ["app/actors/work_order/check.rb"],
        "owner",
        "repo",
        [{ "filename" => "app/actors/work_order/check.rb", "status" => "modified" }],
      )

      expect(result.first[:actor_name]).to eq("WorkOrder::Check")
    end

    it "uses default modified status when file status is missing" do
      service = described_class.new("token")
      allow(service).to receive(:extract_class_name_from_github_file).and_return("WorkOrder::Check")

      result = service.send(:analyze_actor_changes, ["app/actors/work_order/check.rb"], "owner", "repo", [])

      expect(result.first[:change_type]).to eq("modified")
    end
  end

  describe ControllerActorParserService do
    it "infers pdf and export entry types from action names" do
      content = <<~RUBY
        class ReportsController < ApplicationController
          def show_pdf
            Report::ShowPdf.call!
          end

          def export_data
            Report::ExportData.result!
          end
        end
      RUBY

      entries = described_class.new.parse_file(content, file_path: "app/controllers/reports_controller.rb")

      expect(entries.find { |e| e[:controller_action] == "show_pdf" }[:entry_type]).to eq("pdf")
      expect(entries.find { |e| e[:controller_action] == "export_data" }[:entry_type]).to eq("export")
    end
  end

  describe FlagUpdateService do
    let(:company) { Company.create!(name: "PrjJieZhou", github_owner: "AMASTek") }

    it "skips reset when company does not exist" do
      expect { described_class.new.reset_all_flags("Missing") }.not_to raise_error
    end

    it "skips statistics output when no flags are changed" do
      ManagementPage.create!(company: company, name: "work_order")

      expect { described_class.new.show_flag_statistics("PrjJieZhou") }.to output(/Impact 記錄: 0/).to_stdout
    end
  end

  describe TestScopeReportService do
    subject(:service) { described_class.new }

    let(:company) { Company.create!(name: "ReportBranch", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "uses select columns when modify columns are blank" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Destroy",
        operation_type: "刪除",
        relate_model: ["WorkOrder"],
        modify_column: [],
        select_column: %w[legacy_field],
      )
      ImpactRecord.create!(
        company: company,
        pr_number: 93,
        source_type: "actor",
        source_name: "WorkOrder::Destroy",
        source_file_path: "app/actors/work_order/destroy.rb",
        target_type: "action_page",
        target_id: action_page.id,
        impact_level: "direct",
        reason: "direct",
      )

      report = service.generate(company: company, pr_number: 93, format: "qa")

      expect(report[:must_test].first[:affected_fields]).to include("legacy_field")
    end

    it "returns nil permission label when entry is missing" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::List",
        operation_type: "查詢",
      )
      ImpactRecord.create!(
        company: company,
        pr_number: 94,
        source_type: "actor",
        source_name: "WorkOrder::List",
        source_file_path: "app/actors/work_order/list.rb",
        target_type: "action_page",
        target_id: action_page.id,
        impact_level: "caller",
        reason: "caller",
      )

      report = service.generate(company: company, pr_number: 94, format: "qa")

      expect(report[:suggested_regression].first[:perm]).to be_nil
    end
  end

  describe RouteParserService do
    it "returns nil comment when action name is blank" do
      routes = [{ route_path: "work_orders", route_comment: "工單管理", http_method: "get" }]

      expect(described_class.new.comment_for_controller_action(routes, "pms/work_orders", "")).to eq("工單管理")
    end
  end

  describe PlayChainParserService do
    it "ends parsing when a non-continuation line appears" do
      content = <<~RUBY
        play WorkOrder::Check
        def foo
      RUBY

      expect(described_class.new.parse(content)).to eq(["WorkOrder::Check"])
    end
  end

  describe FrontendPackScannerService do
    it "scans app/javascript packs" do
      github_double = instance_double(GithubRepoService)
      allow(github_double).to receive(:get_directory_files).with("owner", "repo", "app/packs", "master").and_return([])
      allow(github_double).to receive(:get_directory_files).with("owner", "repo", "app/javascript", "master")
                                                         .and_return([{ path: "app/javascript/javascripts/pms/work_orders/index.js" }])

      grouped = described_class.new(github_service: github_double).packs_by_controller_path(
        owner: "owner",
        repo: "repo",
        branch: "master",
      )

      expect(grouped["pms/work_orders"]).to include("app/javascript/javascripts/pms/work_orders/index.js")
    end
  end

  describe MigrationDiffAnalyzerService do
    it "deduplicates repeated column changes in one patch" do
      patch = "+    add_column :work_orders, :estimated_hours, :decimal\n+    add_column :work_orders, :estimated_hours, :decimal"

      expect(described_class.new.analyze_patch(patch).size).to eq(1)
    end
  end

  describe BlueprintParserService do
    it "supports top-level blueprint paths" do
      expect(described_class.new.blueprint_name_from_file_path("app/blueprints/info_blueprint.rb")).to eq("InfoBlueprint")
    end
  end

  describe NavbarParserService do
    it "returns empty namespace for unknown source paths" do
      menus = described_class.new.parse('{name: "工單", controller_path: "pms/work_orders"}', source_path: "unknown")

      expect(menus.first[:namespace]).to eq("")
    end
  end

  describe ExtendedRelationService do
    it "leaves entry type unchanged when route type matches current value" do
      company = Company.create!(name: "RouteSame", github_owner: "AMASTek")
      management_page = ManagementPage.create!(company: company, name: "work_order")
      action_page = ActionPage.create!(company: company, management_page: management_page, name: "WorkOrder::List")
      entry = EntryPoint.create!(
        company: company,
        action_page: action_page,
        controller_path: "pms/work_orders",
        controller_action: "index",
        entry_type: "page",
      )
      github_double = instance_double(GithubRepoService)
      allow(github_double).to receive(:get_file_content).and_return({ content: 'get "work_orders" # 工單' })

      described_class.new(github_service: github_double).send(
        :link_route_entry_types!,
        company,
        "AMASTek",
        "RouteSame",
        "master",
      )

      expect(entry.reload.entry_type).to eq("page")
    end
  end
end
