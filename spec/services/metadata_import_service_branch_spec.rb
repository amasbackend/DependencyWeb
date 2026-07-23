# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetadataImportService do
  let(:company) { Company.create!(name: "MetaBranch", github_owner: "AMASTek", github_branch: "master") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Create",
      display_label: "既有標籤",
      play_chain: ["WorkOrder::Check"],
      source_file_path: "app/actors/work_order/create.rb",
    )
  end
  let(:github_double) { instance_double(GithubRepoService) }

  before do
    allow(github_double).to receive(:get_file_content).and_return(nil)
    allow(github_double).to receive(:get_directory_files).and_return([])
  end

  it "fills missing display labels during enrichment" do
    action_page.update!(display_label: nil)

    described_class.new(github_service: github_double).send(:enrich_action_pages!, company, nil)

    action_page.reload
    expect(action_page.display_label).to eq("Create")
    expect(action_page.operation_type).to eq("新增")
  end

  it "records action page enrichment warnings" do
    service = described_class.new(github_service: github_double)
    allow(company).to receive(:action_pages).and_raise(StandardError, "enrich failed")

    service.send(:enrich_action_pages!, company, nil)

    expect(service.warnings.last).to include("ActionPage 擴充失敗")
  end

  it "imports locale from fallback path" do
    allow(github_double).to receive(:get_file_content).with("AMASTek", "MetaBranch", "config/locales/zh-TW/model.yml", "master")
                                                      .and_return(nil)
    allow(github_double).to receive(:get_file_content).with("AMASTek", "MetaBranch", "config/locales/zh-TW.yml", "master")
                                                      .and_return({ content: "zh-TW:\n  perm_module:\n    work_order: 生產管理" })

    locale = described_class.new(github_service: github_double).send(
      :import_locale_metadata!,
      company,
      "AMASTek",
      "MetaBranch",
      "master",
    )

    expect(locale.perm_module_labels["work_order"]).to eq("生產管理")
  end
end
