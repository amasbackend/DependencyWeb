# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlayChainParserService do
  subject(:service) { described_class.new }

  it "extracts actor references from play lines" do
    content = <<~RUBY
      class WorkOrder::Create < Actor
        play :find_component,
             WorkOrder::RefreshEstimatedCompletion
    RUBY

    chain = service.parse(content)
    expect(chain).to include("WorkOrder::RefreshEstimatedCompletion")
  end

  it "parses single-line play statements" do
    content = "play WorkOrder::Check, WorkOrder::Approve"

    expect(service.parse(content)).to contain_exactly("WorkOrder::Check", "WorkOrder::Approve")
  end

  it "returns empty array for blank content" do
    expect(service.parse("")).to eq([])
    expect(service.parse(nil)).to eq([])
  end
end
