# frozen_string_literal: true

require "rails_helper"

RSpec.describe DependencyGraphService do
  let(:company) { Company.create!(name: "TestCo", github_owner: "AMASTek") }
  let(:management_page) { ManagementPage.create!(company: company, name: "work_order") }

  let!(:check_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Check",
      relate_action: [],
      relate_model: ["WorkOrder"],
    )
  end

  let!(:create_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Create",
      relate_action: ["WorkOrder::Check"],
      relate_model: ["WorkOrder", "Component"],
    )
  end

  let!(:approve_page) do
    ActionPage.create!(
      company: company,
      management_page: management_page,
      name: "WorkOrder::Approve",
      relate_action: ["WorkOrder::Create"],
      relate_model: [],
    )
  end

  describe "#callers_of_actor" do
    it "finds one-level callers" do
      graph = described_class.new(company)
      callers = graph.callers_of_actor("WorkOrder::Check", max_depth: 1)

      expect(callers.keys).to contain_exactly(create_page)
      expect(callers[create_page]).to eq(1)
    end

    it "finds two-level callers" do
      graph = described_class.new(company)
      callers = graph.callers_of_actor("WorkOrder::Check", max_depth: 2)

      expect(callers[create_page]).to eq(1)
      expect(callers[approve_page]).to eq(2)
    end
  end

  describe "model consumers" do
    it "maps model names to action pages" do
      graph = described_class.new(company)

      expect(graph.model_consumers_of["Component"]).to contain_exactly(create_page)
    end
  end

  describe "play chain callers" do
    before do
      create_page.update!(play_chain: ["WorkOrder::Check"])
    end

    it "includes play_chain actors when resolving callers" do
      graph = described_class.new(company)
      callers = graph.callers_of_actor("WorkOrder::Check", max_depth: 1)

      expect(callers.keys).to include(create_page)
    end
  end

  describe "caller traversal edge cases" do
    it "skips already visited callers in deeper traversal" do
      create_page.update!(relate_action: ["WorkOrder::Check", "WorkOrder::Approve"])
      approve_page.update!(relate_action: ["WorkOrder::Check"])

      graph = described_class.new(company)
      callers = graph.callers_of_actor("WorkOrder::Check", max_depth: 2)

      expect(callers.keys).to include(create_page, approve_page)
    end
  end
end
