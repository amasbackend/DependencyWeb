# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Final service branch coverage" do
  describe GithubAnalysisService do
    it "checks PR existence with short response bodies and no token" do
      response = instance_double(Net::HTTPResponse, code: "404", body: "short")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = described_class.new(nil).check_pr_exists("owner", "repo", 1)

      expect(result[:exists]).to be false
    end

    it "skips invalid actor paths without a filename match" do
      service = described_class.new("token")
      allow(service).to receive(:extract_class_name_from_github_file).and_return(nil)

      result = service.send(
        :analyze_actor_changes,
        ["app/actors/invalid.rb"],
        "owner",
        "repo",
        [{ "filename" => "app/actors/invalid.rb", "status" => "modified" }],
      )

      expect(result).to be_empty
    end

    it "skips model files that do not match the expected path pattern" do
      service = described_class.new("token")

      result = service.send(
        :analyze_model_changes,
        ["app/models/nested/work_order.rb"],
        [{ "filename" => "app/models/nested/work_order.rb", "status" => "modified" }],
      )

      expect(result).to be_empty
    end

    it "fetches file content without an access token" do
      service = described_class.new("token")
      service.instance_variable_set(:@access_token, nil)
      response = instance_double(Net::HTTPResponse, code: "500", body: "error")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.send(:extract_class_name_from_github_file, "app/actors/x.rb", "owner", "repo")).to be_nil
    end
  end

  describe GithubRepoService do
    it "omits branch query params when branch is nil" do
      service = described_class.new(nil)
      response = instance_double(Net::HTTPResponse, code: "200", body: [].to_json)
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.uri.query).to be_nil
        response
      end

      service.get_subdirectories("owner", "repo", "app/actors", nil)
    end

    it "recurses into child directories when listing files" do
      service = described_class.new("token")
      root = instance_double(Net::HTTPResponse, code: "200", body: [{ "type" => "dir", "path" => "app/packs/src" }].to_json)
      leaf = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: [{ "type" => "file", "path" => "app/packs/src/file.js", "name" => "file.js", "size" => 1 }].to_json,
      )
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http).and_yield(http)
      allow(http).to receive(:request).and_return(root, leaf)

      files = service.get_directory_files("owner", "repo", "app/packs")

      expect(files.map { |f| f[:path] }).to include("app/packs/src/file.js")
    end

    it "builds unauthorized requests when token is missing" do
      service = described_class.new("token")
      service.instance_variable_set(:@access_token, nil)
      request = service.send(:build_request, URI("https://api.github.com/repos/o/r/contents"))

      expect(request["Authorization"]).to be_nil
    end
  end

  describe ImpactAnalysisService do
    let(:company) { Company.create!(name: "FinalImpact", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "covers nil-safe metadata on callers, models, and controllers" do
      check_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Check",
        relate_action: [],
        relate_model: ["WorkOrder"],
      )
      create_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Create",
        relate_action: ["WorkOrder::Check"],
        relate_model: ["WorkOrder"],
      )
      relate_model = RelateModel.create!(management_page: management_page, action_page: check_page, name: "WorkOrder")
      blueprint_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Show",
        blueprint_names: ["WorkOrder::InfoBlueprint"],
      )
      SharedConcern.create!(
        company: company,
        action_page: check_page,
        concern_name: "WorkOrderHelper",
        concern_file_path: "app/actors/concerns/work_order_helper.rb",
      )
      EntryPoint.create!(
        company: company,
        action_page: check_page,
        controller_path: "pms/work_orders",
        controller_action: "update",
      )

      allow_any_instance_of(ActionPage).to receive(:management_page).and_return(nil)
      allow_any_instance_of(RelateModel).to receive(:management_page).and_return(nil)
      allow_any_instance_of(RelateModel).to receive(:action_page).and_return(nil)

      impacts = described_class.new.analyze(
        company: company,
        pr_number: 1,
        actor_changes: [{ actor_name: "WorkOrder::Check", file_path: "app/actors/work_order/check.rb" }],
        model_changes: [{ model_name: "WorkOrder", file_path: "app/models/work_order.rb" }],
        controller_changes: [{ controller_path: "pms/work_orders", file_path: "app/controllers/pms/work_orders_controller.rb" }],
        migration_changes: [
          {
            file_path: "db/migrate/20260101000000_add_hours.rb",
            column_impacts: [{ table: "work_orders", column: "name", change_type: "add_column", model_name: "WorkOrder" }],
          },
        ],
        concern_changes: [{ concern_name: "WorkOrderHelper", file_path: "app/actors/concerns/work_order_helper.rb" }],
        blueprint_changes: [{ blueprint_name: "WorkOrder::InfoBlueprint", file_path: "app/blueprints/work_order/info_blueprint.rb" }],
      )

      expect(impacts.map { |impact| impact[:target_id] }).to include(check_page.id, create_page.id, blueprint_page.id, relate_model.id)
    end
  end

  describe TestScopeReportService do
    let(:company) { Company.create!(name: "FinalReport", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "handles non-action-page impacts and missing associations in tech view" do
      ImpactRecord.create!(
        company: company,
        pr_number: 95,
        source_type: "model",
        source_name: "WorkOrder",
        source_file_path: "app/models/work_order.rb",
        target_type: "relate_model",
        target_id: 99_999,
        impact_level: "direct",
        reason: "missing model",
      )
      ImpactRecord.create!(
        company: company,
        pr_number: 95,
        source_type: "controller",
        source_name: "pms/work_orders",
        source_file_path: "app/controllers/pms/work_orders_controller.rb",
        target_type: "entry_point",
        target_id: 99_998,
        impact_level: "direct",
        reason: "missing entry",
      )

      report = described_class.new.generate(company: company, pr_number: 95, format: "tech")

      expect(report[:impacts].map { |row| row[:target_name] }).to eq([nil, nil])
    end

    it "classifies concern impacts as suggested regression" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Update",
        operation_type: "編輯",
      )
      ImpactRecord.create!(
        company: company,
        pr_number: 96,
        source_type: "concern",
        source_name: "WorkOrderHelper",
        source_file_path: "app/actors/concerns/work_order_helper.rb",
        target_type: "action_page",
        target_id: action_page.id,
        impact_level: "concern",
        reason: "concern",
      )

      report = described_class.new.generate(company: company, pr_number: 96, format: "qa")

      expect(report[:suggested_regression].size).to eq(1)
    end

    it "falls back to management page when entry and menu are missing" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::List",
        operation_type: "查詢",
      )
      ImpactRecord.create!(
        company: company,
        pr_number: 97,
        source_type: "actor",
        source_name: "WorkOrder::List",
        source_file_path: "app/actors/work_order/list.rb",
        target_type: "action_page",
        target_id: action_page.id,
        impact_level: "caller",
        reason: "caller",
      )

      report = described_class.new.generate(company: company, pr_number: 97, format: "qa")

      expect(report[:suggested_regression].first[:menu_path]).to eq("work_order")
    end
  end

  describe MetadataImportService do
    let(:company) { Company.create!(name: "FinalMeta", github_owner: "AMASTek") }
    let(:github_double) { instance_double(GithubRepoService) }

    before do
      ManagementPage.create!(company: company, name: "work_order")
      allow(github_double).to receive(:get_file_content).and_return(nil)
      allow(github_double).to receive(:get_directory_files).and_return([])
    end

    it "clears metadata even when locale metadata is absent" do
      expect { described_class.new(github_service: github_double).send(:clear_metadata!, company) }.not_to raise_error
    end

    it "imports navbar menus without perm module labels" do
      allow(github_double).to receive(:get_directory_files).with("AMASTek", "FinalMeta", "app/views", "master")
                                                         .and_return([{ path: "app/views/pms/_navbar.html.erb" }])
      allow(github_double).to receive(:get_file_content).with("AMASTek", "FinalMeta", "app/views/pms/_navbar.html.erb", "master")
                                                        .and_return({
                                                                      content: '{name: "工單管理", controller_path: "pms/work_orders"}',
                                                                    })

      menus = described_class.new(github_service: github_double).send(
        :import_ui_menus!,
        company,
        "AMASTek",
        "FinalMeta",
        "master",
        nil,
      )

      expect(menus.first.module_label).to be_nil
    end

    it "does not overwrite existing play chains during enrichment" do
      action_page = ActionPage.create!(
        company: company,
        management_page: company.management_pages.first,
        name: "WorkOrder::Create",
        source_file_path: "app/actors/work_order/create.rb",
        play_chain: ["WorkOrder::Check"],
      )

      described_class.new(github_service: github_double).send(:enrich_action_pages!, company, nil)

      expect(action_page.reload.play_chain).to eq(["WorkOrder::Check"])
    end
  end

  describe DependencyGraphService do
    it "does not revisit callers already in the result set" do
      company = Company.create!(name: "GraphFinal", github_owner: "AMASTek")
      management_page = ManagementPage.create!(company: company, name: "work_order")
      check = ActionPage.create!(company: company, management_page: management_page, name: "WorkOrder::Check", relate_action: [], relate_model: [])
      create = ActionPage.create!(company: company, management_page: management_page, name: "WorkOrder::Create", relate_action: %w[WorkOrder::Check WorkOrder::Check], relate_model: [])

      callers = described_class.new(company).callers_of_actor("WorkOrder::Check", max_depth: 1)

      expect(callers.keys).to eq([create])
    end
  end

  describe ControllerActorParserService do
    it "returns page entry type for regular actions" do
      content = <<~RUBY
        class Pms::WorkOrdersController < ApplicationController
          def index
            WorkOrder::List.call!
          end
        end
      RUBY

      entry = described_class.new.parse_file(content, file_path: "app/controllers/pms/work_orders_controller.rb").first

      expect(entry[:entry_type]).to eq("page")
    end
  end

  describe PlayChainParserService do
    it "finalizes buffered play args at end of file" do
      expect(described_class.new.parse("play WorkOrder::Check")).to eq(["WorkOrder::Check"])
    end
  end

  describe RouteParserService do
    it "returns nil comment when route comment is blank" do
      routes = [{ route_path: "work_orders", route_comment: "", http_method: "get" }]

      expect(described_class.new.comment_for_controller_action(routes, "pms/work_orders", "index")).to be_nil
    end
  end
end
