# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpecScannerService do
  subject(:service) { described_class.new }

  let(:github_double) { instance_double(GithubRepoService) }

  before do
    allow(github_double).to receive(:get_directory_files).and_return([
                                                                       { path: "spec/actors/examine_record/keyence_measurement_spec.rb" },
                                                                     ])
  end

  it "maps spec path to actor class name" do
    name = service.actor_name_from_spec_path("spec/actors/examine_record/keyence_measurement_spec.rb")
    expect(name).to eq("ExamineRecord::KeyenceMeasurement")
  end

  it "collects actor names with specs from GitHub" do
    scanner = described_class.new(github_service: github_double)

    expect(scanner.actor_names_with_specs(owner: "owner", repo: "repo", branch: "master"))
      .to eq(["ExamineRecord::KeyenceMeasurement"])
  end

  it "returns nil for non-spec paths" do
    expect(service.actor_name_from_spec_path("spec/models/work_order_spec.rb")).to be_nil
  end
end
