# frozen_string_literal: true

require "rails_helper"
require "net/http"

RSpec.describe GithubRepoService do
  subject(:service) { described_class.new("test-token") }

  describe "#get_subdirectories" do
    let(:response) { instance_double(Net::HTTPResponse, code: "200", body: body) }
    let(:body) do
      [
        { "type" => "dir", "name" => "work_order" },
        { "type" => "file", "name" => "create.rb" },
      ].to_json
    end

    before do
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))
    end

    it "returns subdirectory names" do
      expect(service.get_subdirectories("owner", "repo", "app/actors")).to eq(["work_order"])
    end

    it "returns empty list on API failure" do
      response = instance_double(Net::HTTPResponse, code: "500", body: "error")
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.get_subdirectories("owner", "repo", "app/actors")).to eq([])
    end
  end

  describe "#get_file_content" do
    before do
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))
    end

    context "when file exists" do
      let(:response) do
        instance_double(
          Net::HTTPResponse,
          code: "200",
          body: {
            "type" => "file",
            "path" => "config/routes.rb",
            "content" => Base64.encode64("get '/'"),
            "sha" => "abc",
          }.to_json,
        )
      end

      it "returns decoded file content" do
        file = service.get_file_content("owner", "repo", "config/routes.rb")

        expect(file[:content]).to include("get")
        expect(file[:content].encoding.name).to eq("UTF-8")
        expect(file[:path]).to eq("config/routes.rb")
      end
    end

    context "when response is a directory" do
      let(:response) { instance_double(Net::HTTPResponse, code: "200", body: { "type" => "dir" }.to_json) }

      it "returns nil" do
        expect(service.get_file_content("owner", "repo", "app/controllers")).to be_nil
      end
    end

    context "when request fails" do
      let(:response) { instance_double(Net::HTTPResponse, code: "404", body: "Not Found") }

      it "returns nil" do
        expect(service.get_file_content("owner", "repo", "missing.rb")).to be_nil
      end
    end
  end

  describe "#get_directory_files" do
    it "recursively collects files" do
      root_response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: [{ "type" => "dir", "path" => "app/actors/work_order" }].to_json,
      )
      leaf_response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: [{ "type" => "file", "path" => "app/actors/work_order/create.rb", "name" => "create.rb", "size" => 10 }].to_json,
      )

      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: root_response))
                                           .and_yield(instance_double(Net::HTTP, request: leaf_response))

      files = service.get_directory_files("owner", "repo", "app/actors")

      expect(files).to contain_exactly(hash_including(path: "app/actors/work_order/create.rb"))
    end

    it "handles API errors gracefully" do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, "network down")

      expect(service.get_directory_files("owner", "repo", "app/actors")).to eq([])
    end
  end
end
