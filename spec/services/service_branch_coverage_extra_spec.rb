# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Additional service branch coverage" do
  describe GithubAnalysisService do
    it "fetches PR files without an access token" do
      response = instance_double(Net::HTTPResponse, code: "200", body: [].to_json)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(described_class.new(nil).get_pr_files("owner", "repo", 1)).to eq([])
    end

    it "analyzes model changes with missing status" do
      service = described_class.new("token")

      result = service.send(:analyze_model_changes, ["app/models/work_order.rb"], [])

      expect(result.first[:change_type]).to eq("modified")
    end

    it "returns empty blueprint list when parser cannot resolve name" do
      service = described_class.new("token")
      allow(BlueprintParserService).to receive(:new).and_return(
        instance_double(BlueprintParserService, blueprint_name_from_file_path: nil),
      )

      expect(service.send(:analyze_blueprint_changes, [{ filename: "app/blueprints/x.rb", status: "modified" }])).to eq([])
    end
  end

  describe GithubRepoService do
    it "rescues subdirectory listing errors" do
      service = described_class.new("token")
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, "broken")

      expect(service.get_subdirectories("owner", "repo", "app/actors")).to eq([])
    end

    it "lists files in a single directory without recursion" do
      service = described_class.new("token")
      response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: [{ "type" => "file", "path" => "app/actors/create.rb", "name" => "create.rb", "size" => 1 }].to_json,
      )
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.get_directory_files("owner", "repo", "app/actors")).to contain_exactly(
        hash_including(path: "app/actors/create.rb"),
      )
    end
  end

  describe MetadataImportService do
    let(:company) { Company.create!(name: "MetaMore", github_owner: "AMASTek") }
    let(:github_double) { instance_double(GithubRepoService) }

    before do
      ManagementPage.create!(company: company, name: "work_order")
      allow(github_double).to receive(:get_file_content).and_return(nil)
      allow(github_double).to receive(:get_directory_files).and_return([])
    end

    it "creates entry points even when actor is not imported yet" do
      allow(github_double).to receive(:get_directory_files).with("AMASTek", "MetaMore", "app/controllers", "master")
                                                         .and_return([{ path: "app/controllers/pms/work_orders_controller.rb" }])
      allow(github_double).to receive(:get_file_content).with("AMASTek", "MetaMore", "app/controllers/pms/work_orders_controller.rb", "master")
                                                        .and_return({
                                                                      content: <<~RUBY,
                                                                        class Pms::WorkOrdersController < ApplicationController
                                                                          def create
                                                                            WorkOrder::Create.call!
                                                                          end
                                                                        end
                                                                      RUBY
                                                                    })

      described_class.new(github_service: github_double).send(
        :import_entry_points!,
        company,
        "AMASTek",
        "MetaMore",
        "master",
        [],
        [],
      )

      expect(company.entry_points.count).to eq(1)
      expect(company.entry_points.first.action_page).to be_nil
    end
  end

  describe ImpactAnalysisService do
    let(:company) { Company.create!(name: "ImpactMore", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "matches underscored column aliases" do
      action_page = ActionPage.create!(
        company: company,
        management_page: management_page,
        name: "WorkOrder::Update",
        relate_model: ["WorkOrder"],
        modify_column: %w[estimatedHours],
      )

      matched = described_class.new.send(:column_referenced?, action_page, "estimated_hours")

      expect(matched).to be true
    end
  end

  describe FlagUpdateService do
    let(:company) { Company.create!(name: "PrjJieZhou", github_owner: "AMASTek") }
    let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

    it "prints relate model list when flags are set" do
      action_page = ActionPage.create!(company: company, management_page: management_page, name: "WorkOrder::Check", changed_flag: true)
      RelateModel.create!(management_page: management_page, action_page: action_page, name: "WorkOrder", changed_flag: true)

      expect { described_class.new.show_flag_statistics("PrjJieZhou") }.to output(/WorkOrder::Check\/WorkOrder/).to_stdout
    end
  end

  describe PrFileClassifierService do
    it "returns nil for invalid controller paths" do
      expect(described_class.new.controller_path_from_file("README.md")).to be_nil
    end
  end

  describe PlayChainParserService do
    it "ignores segments without actor constants" do
      expect(described_class.new.parse("play 123, :symbol")).to eq([])
    end
  end

  describe RouteParserService do
    it "returns page entry type for pdf-only action names" do
      expect(described_class.new.entry_type_for_controller_action([], "pms/work_orders", "index")).to eq("page")
    end
  end
end
