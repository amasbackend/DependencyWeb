# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubAnalysisService do
  subject(:service) { described_class.new("test-token") }

  let(:pr_files) do
    [
      {
        "filename" => "app/actors/work_order/check.rb",
        "status" => "modified",
      },
      {
        "filename" => "app/models/component.rb",
        "status" => "modified",
      },
      {
        "filename" => "app/controllers/pms/work_orders_controller.rb",
        "status" => "modified",
      },
      {
        "filename" => "db/migrate/20260101000000_add_hours.rb",
        "status" => "modified",
        "patch" => "+    add_column :work_orders, :estimated_hours, :decimal",
      },
      {
        "filename" => "app/actors/concerns/work_order_helper.rb",
        "status" => "modified",
      },
      {
        "filename" => "app/blueprints/work_order/info_blueprint.rb",
        "status" => "modified",
      },
      {
        "filename" => "config/routes.rb",
        "status" => "modified",
      },
      {
        "filename" => "README.md",
        "status" => "modified",
      },
    ]
  end

  before do
    allow(service).to receive(:check_pr_exists).and_return(exists: true, status_code: "200", body: "{}")
    allow(service).to receive(:get_pr_files).and_return(pr_files)
    allow(service).to receive(:extract_class_name_from_github_file).and_return("WorkOrder::Check")
  end

  describe "#check_pr_exists" do
    it "reports whether PR exists without token" do
      response = instance_double(Net::HTTPResponse, code: "200", body: "{}")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = described_class.new(nil).check_pr_exists("owner", "repo", 65)

      expect(result[:exists]).to be true
    end

    it "reports missing PR" do
      response = instance_double(Net::HTTPResponse, code: "404", body: "missing")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      result = described_class.new("token").check_pr_exists("owner", "repo", 65)

      expect(result[:exists]).to be false
    end
  end

  describe "#get_pr_files" do
    it "returns parsed file list" do
      response = instance_double(Net::HTTPResponse, code: "200", body: pr_files.to_json)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(described_class.new("token").get_pr_files("owner", "repo", 65).size).to eq(pr_files.size)
    end

    it "raises on API error" do
      response = instance_double(Net::HTTPResponse, code: "404", body: "missing")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect do
        described_class.new("token").get_pr_files("owner", "repo", 65)
      end.to raise_error(/GitHub API 錯誤/)
    end
  end

  describe "#analyze_changes" do
    it "classifies changed files into analysis buckets" do
      result = service.analyze_changes("owner", "repo", 65)

      expect(result[:actor_changes].map { |c| c[:actor_name] }).to include("WorkOrder::Check")
      expect(result[:model_changes].map { |c| c[:model_name] }).to include("Component")
      expect(result[:controller_changes].first[:controller_path]).to eq("pms/work_orders")
      expect(result[:migration_changes].first[:column_impacts]).not_to be_empty
      expect(result[:concern_changes].first[:concern_name]).to eq("WorkOrderHelper")
      expect(result[:blueprint_changes].first[:blueprint_name]).to eq("WorkOrder::InfoBlueprint")
      expect(result[:route_changes].size).to eq(1)
      expect(result[:classified_counts]["actor"]).to eq(1)
      expect(result[:classified_counts]["other"]).to eq(1)
    end

    it "raises when PR does not exist" do
      allow(service).to receive(:check_pr_exists).and_return(exists: false, status_code: "404")

      expect do
        service.analyze_changes("owner", "repo", 999)
      end.to raise_error(/PR 不存在/)
    end
  end

  describe "actor change extraction" do
    it "falls back to filename when class extraction returns nil" do
      allow(service).to receive(:extract_class_name_from_github_file).and_return(nil)

      result = service.send(
        :analyze_actor_changes,
        ["app/actors/work_order/check.rb"],
        "owner",
        "repo",
        [{ "filename" => "app/actors/work_order/check.rb", "status" => "added" }],
      )

      expect(result.first[:actor_name]).to eq("check")
    end

    it "skips concern files and non-actor paths" do
      result = service.send(
        :analyze_actor_changes,
        ["app/actors/concerns/helper.rb", "app/models/work_order.rb"],
        "owner",
        "repo",
        [],
      )

      expect(result).to be_empty
    end
  end

  describe "model change extraction" do
    it "skips nested model paths" do
      result = service.send(
        :analyze_model_changes,
        ["app/models/concerns/trackable.rb"],
        [],
      )

      expect(result).to be_empty
    end
  end

  describe "#extract_class_name_from_github_file" do
    let(:bare_service) { described_class.new("token") }

    it "falls back to filename when API content is unavailable" do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, "timeout")

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/work_order/check.rb",
        "owner",
        "repo",
      )

      expect(class_name).to eq("check")
    end

    it "extracts class name from file content with inheritance" do
      file_body = {
        "content" => Base64.encode64("class WorkOrder::Check < Actor\nend"),
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: file_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/work_order/check.rb",
        "owner",
        "repo",
      )

      expect(class_name).to eq("WorkOrder::Check")
    end

    it "extracts class name without inheritance syntax" do
      file_body = {
        "content" => Base64.encode64("class WorkOrder::Check\nend"),
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: file_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/work_order/check.rb",
        "owner",
        "repo",
      )

      expect(class_name).to eq("WorkOrder::Check")
    end

    it "skips module definitions" do
      file_body = {
        "content" => Base64.encode64("module WorkOrder::Check\nend"),
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: file_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/work_order/check.rb",
        "owner",
        "repo",
      )

      expect(class_name).to eq("check")
    end

    it "returns nil when content has no class or path match" do
      file_body = {
        "content" => Base64.encode64("# empty\n"),
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: file_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/invalid.rb",
        "owner",
        "repo",
      )

      expect(class_name).to be_nil
    end

    it "returns nil for non-200 responses without actor path fallback" do
      response = instance_double(Net::HTTPResponse, code: "500", body: "error")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = bare_service.send(
        :extract_class_name_from_github_file,
        "app/actors/invalid.rb",
        "owner",
        "repo",
      )

      expect(class_name).to be_nil
    end
  end
end
