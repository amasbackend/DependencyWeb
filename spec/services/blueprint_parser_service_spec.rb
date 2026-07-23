# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlueprintParserService do
  subject(:service) { described_class.new }

  it "extracts blueprint references from actor content" do
    content = 'Order::InfoBlueprint.render_as_hash(order)'
    expect(service.parse(content)).to eq(["Order::InfoBlueprint"])
  end

  it "returns empty array for blank content" do
    expect(service.parse("")).to eq([])
  end

  it "maps blueprint file path to class name" do
    name = service.blueprint_name_from_file_path("app/blueprints/work_order/info_blueprint.rb")
    expect(name).to eq("WorkOrder::InfoBlueprint")
  end

  it "returns nil for empty blueprint paths" do
    expect(service.blueprint_name_from_file_path("app/blueprints/")).to be_nil
  end
end
