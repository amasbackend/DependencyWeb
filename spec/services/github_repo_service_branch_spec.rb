# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubRepoService do
  describe "branch coverage" do
    it "builds requests without access token" do
      service = described_class.new(nil)
      response = instance_double(Net::HTTPResponse, code: "200", body: [].to_json)
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.get_subdirectories("owner", "repo", "app/actors", "main")).to eq([])
    end

    it "handles directory listing failures in recursive fetch" do
      service = described_class.new("token")
      ok_response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: [{ "type" => "dir", "path" => "app/actors/work_order" }].to_json,
      )
      fail_response = instance_double(Net::HTTPResponse, code: "500", body: "error")

      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: ok_response))
                                           .and_yield(instance_double(Net::HTTP, request: fail_response))

      files = service.get_directory_files("owner", "repo", "app/actors")

      expect(files).to eq([])
    end

    it "rescues file fetch errors" do
      service = described_class.new("token")
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, "broken")

      expect(service.get_file_content("owner", "repo", "config/routes.rb")).to be_nil
    end

    it "returns nil when file payload has no content" do
      service = described_class.new("token")
      response = instance_double(
        Net::HTTPResponse,
        code: "200",
        body: { "type" => "file", "path" => "config/routes.rb" }.to_json,
      )
      allow(Net::HTTP).to receive(:start).and_yield(instance_double(Net::HTTP, request: response))

      expect(service.get_file_content("owner", "repo", "config/routes.rb")).to be_nil
    end
  end
end
