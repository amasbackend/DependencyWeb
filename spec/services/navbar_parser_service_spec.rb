# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavbarParserService do
  subject(:service) { described_class.new }

  let(:content) do
    <<~ERB
      modules = [
        {name: "工單管理", path: pms_work_orders_path, controller_path: "pms/work_orders", perm_module: "work_order", actions: %w[index new] },
      ]
    ERB
  end

  it "parses PrjJieZhou style navbar entries" do
    menus = service.parse(content, source_path: "app/views/pms/_navbar.html.erb")

    expect(menus.size).to eq(1)
    expect(menus.first[:menu_label]).to eq("工單管理")
    expect(menus.first[:controller_path]).to eq("pms/work_orders")
    expect(menus.first[:namespace]).to eq("pms")
    expect(menus.first[:actions]).to eq(%w[index new])
    expect(menus.first[:perm_module]).to eq("work_order")
  end

  it "returns empty array for blank content" do
    expect(service.parse("", source_path: nil)).to eq([])
  end

  it "skips entries without controller path" do
    invalid = '{name: "工單管理", controller_path: ""}'

    expect(service.parse(invalid)).to eq([])
  end

  it "deduplicates repeated navbar entries" do
    duplicate = <<~ERB
      modules = [
        {name: "工單管理", path: pms_work_orders_path, controller_path: "pms/work_orders", perm_module: "work_order", actions: %w[index] },
        {name: "工單管理", path: pms_work_orders_path, controller_path: "pms/work_orders", perm_module: "work_order", actions: %w[index] },
      ]
    ERB

    expect(service.parse(duplicate, source_path: "app/views/pms/_navbar.html.erb").size).to eq(1)
  end
end
