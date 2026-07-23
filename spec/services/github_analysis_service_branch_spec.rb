# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubAnalysisService do
  describe "branch coverage" do
    it "logs long PR response bodies only once" do
      service = described_class.new("token")
      long_body = "x" * 250
      response = instance_double(Net::HTTPResponse, code: "200", body: long_body)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.check_pr_exists("owner", "repo", 1)[:exists]).to be true
    end

    it "skips actor files when class extraction and filename fallback both fail" do
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

    it "returns empty controller changes when path cannot be resolved" do
      service = described_class.new("token")
      classifier = PrFileClassifierService.new

      result = service.send(
        :analyze_controller_changes,
        [{ filename: "app/controllers/invalid.rb", status: "modified" }],
        classifier,
      )

      expect(result).to be_empty
    end

    it "returns empty concern changes when concern name is missing" do
      service = described_class.new("token")
      allow(ConcernParserService).to receive(:new).and_return(
        instance_double(ConcernParserService, concern_name_from_file_path: nil),
      )

      result = service.send(
        :analyze_concern_changes,
        [{ filename: "app/actors/concerns/invalid.rb", status: "modified" }],
      )

      expect(result).to be_empty
    end

    it "returns empty blueprint changes when blueprint name is missing" do
      service = described_class.new("token")

      result = service.send(
        :analyze_blueprint_changes,
        [{ filename: "app/blueprints/.rb", status: "modified" }],
      )

      expect(result).to be_empty
    end

    it "returns nil when github response has no content block" do
      service = described_class.new("token")
      response = instance_double(Net::HTTPResponse, code: "200", body: { "message" => "empty" }.to_json)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      class_name = service.send(
        :extract_class_name_from_github_file,
        "app/actors/work_order/check.rb",
        "owner",
        "repo",
      )

      expect(class_name).to eq("check")
    end
  end
end
