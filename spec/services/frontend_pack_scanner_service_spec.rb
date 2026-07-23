# frozen_string_literal: true

require "rails_helper"

RSpec.describe FrontendPackScannerService do
  subject(:service) { described_class.new }

  let(:github_double) { instance_double(GithubRepoService) }

  before do
    allow(github_double).to receive(:get_directory_files).with("owner", "repo", "app/packs", "master")
                                                         .and_return([{ path: "app/packs/src/javascripts/pms/work_orders/form.js" }])
    allow(github_double).to receive(:get_directory_files).with("owner", "repo", "app/javascript", "master")
                                                         .and_return([])
  end

  it "maps pack javascript path to controller path" do
    path = service.controller_path_from_pack("app/packs/src/javascripts/pms/work_orders/form.js")
    expect(path).to eq("pms/work_orders")
  end

  it "groups pack files by controller path" do
    grouped = described_class.new(github_service: github_double).packs_by_controller_path(
      owner: "owner",
      repo: "repo",
      branch: "master",
    )

    expect(grouped["pms/work_orders"]).to include("app/packs/src/javascripts/pms/work_orders/form.js")
  end

  it "returns nil for unrelated paths" do
    expect(service.controller_path_from_pack("app/assets/stylesheets/site.css")).to be_nil
  end
end
