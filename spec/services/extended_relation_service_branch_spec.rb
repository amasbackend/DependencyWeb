# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtendedRelationService do
  let(:company) { Company.create!(name: "ExtBranch", github_owner: "AMASTek", github_branch: "master") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }
  let!(:action_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::List",
    )
  end
  let(:github_double) { instance_double(GithubRepoService) }

  before do
    allow(github_double).to receive(:get_directory_files).and_return([])
    allow(github_double).to receive(:get_file_content).and_return(nil)
  end

  it "skips related file attachment when controller has no packs" do
    EntryPoint.create!(
      company: company,
      action_page: action_page,
      controller_path: "pms/work_orders",
      controller_action: "index",
    )

    described_class.new(github_service: github_double).send(
      :attach_related_files!,
      company,
      action_page,
      {},
    )

    expect(action_page.reload.related_files).to be_nil
  end

  it "records route entry type warnings" do
    EntryPoint.create!(
      company: company,
      action_page: action_page,
      controller_path: "pms/work_orders",
      controller_action: "index",
      entry_type: "page",
    )
    allow(github_double).to receive(:get_file_content).and_raise(StandardError, "routes down")

    service = described_class.new(github_service: github_double)
    service.send(:link_route_entry_types!, company, "AMASTek", "ExtBranch", "master")

    expect(service.warnings.last).to include("Route entry_type 標記失敗")
  end
end
