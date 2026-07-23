# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtendedRelationService do
  let(:company) { Company.create!(name: "TestCo", github_owner: "AMASTek", github_branch: "master") }
  let(:management_page) { ManagementPage.create!(company: company, name: "examine_record") }
  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "ExamineRecord::KeyenceMeasurement",
      relate_model: ["ExamineRecord"],
    )
  end
  let!(:entry_point) do
    EntryPoint.create!(
      company: company,
      action_page: action_page,
      controller_path: "pms/examine_records",
      controller_action: "show",
    )
  end

  let(:github_double) { instance_double(GithubRepoService) }

  before do
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "spec/actors", "master")
                                                         .and_return([
                                                                       { path: "spec/actors/examine_record/keyence_measurement_spec.rb" },
                                                                     ])
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/packs", "master")
                                                         .and_return([
                                                                       { path: "app/packs/src/javascripts/pms/examine_records/show.js" },
                                                                     ])
    allow(github_double).to receive(:get_directory_files).with("AMASTek", "TestCo", "app/javascript", "master")
                                                         .and_return([])
    allow(github_double).to receive(:get_file_content).and_return(nil)
  end

  it "marks has_spec and related frontend pack files" do
    summary = described_class.new(github_service: github_double).enrich!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(summary[:specs_matched]).to eq(1)
    expect(action_page.reload.has_spec).to be true
    expect(action_page.related_files).to include("app/packs/src/javascripts/pms/examine_records/show.js")
  end

  it "updates entry point types from routes" do
    allow(github_double).to receive(:get_file_content).with("AMASTek", "TestCo", "config/routes.rb", "master")
                                                      .and_return({
                                                                    content: 'get "examine_records/export_pdf" # 匯出',
                                                                  })

    described_class.new(github_service: github_double).enrich!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(entry_point.reload.entry_type).to eq("pdf")
  end

  it "records warnings when enrichment fails" do
    allow(github_double).to receive(:get_directory_files).and_raise(StandardError, "boom")

    summary = described_class.new(github_service: github_double).enrich!(
      company: company,
      owner: "AMASTek",
      repo: "TestCo",
      branch: "master",
    )

    expect(summary[:warnings].last).to include("Extended relations 匯入失敗")
  end
end
