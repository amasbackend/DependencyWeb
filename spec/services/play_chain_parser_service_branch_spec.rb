# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlayChainParserService do
  subject(:service) { described_class.new }

  it "parses multiple play blocks in one file" do
    content = <<~RUBY
      class WorkOrder::Create < Actor
        play WorkOrder::Check

        def other
        end

        play WorkOrder::Approve
    RUBY

    expect(service.parse(content)).to contain_exactly("WorkOrder::Check", "WorkOrder::Approve")
  end

  it "ignores symbol-only play segments" do
    content = "play :prepare, :validate"

    expect(service.parse(content)).to eq([])
  end
end
