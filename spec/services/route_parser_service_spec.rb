# frozen_string_literal: true

require "rails_helper"

RSpec.describe RouteParserService do
  subject(:service) { described_class.new }

  describe "#parse" do
    it "parses HTTP routes with comments" do
      content = <<~RUBY
        get "work_orders/export", to: "work_orders/export" # 匯出報表
        post "work_orders", to: "work_orders/create" # 新增工單
      RUBY

      routes = service.parse(content)

      expect(routes.size).to eq(2)
      expect(routes.first).to include(
        route_path: "work_orders/export",
        route_comment: "匯出報表",
        http_method: "get",
        entry_type: "export",
      )
      expect(routes.second[:entry_type]).to eq("page")
    end

    it "parses resources routes" do
      content = 'resources :work_orders # 工單管理'

      routes = service.parse(content)

      expect(routes).to contain_exactly(
        hash_including(route_path: "work_orders", route_comment: "工單管理", resource: true, entry_type: "page"),
      )
    end

    it "skips blank lines and comments without route definitions" do
      expect(service.parse("")).to eq([])
      expect(service.parse("# only comment\n")).to eq([])
    end

  it "infers export entry type from comment" do
    content = "get \"reports/export\" # 匯出報表".dup.force_encoding("ASCII-8BIT")

    routes = service.parse(content)

    expect(routes.first[:entry_type]).to eq("export")
  end
  end

  describe "#comment_for_controller_action" do
    let(:routes) do
      [
        { route_path: "work_orders", route_comment: "工單管理", http_method: "get" },
      ]
    end

    it "finds comment for matching controller segment" do
      comment = service.comment_for_controller_action(routes, "pms/work_orders", "index")

      expect(comment).to eq("工單管理")
    end

    it "returns nil when controller segment is blank" do
      expect(service.comment_for_controller_action(routes, "", "index")).to be_nil
    end

    it "returns nil when no route matches controller segment" do
      expect(service.comment_for_controller_action([], "pms/work_orders", "index")).to be_nil
    end
  end

  describe "#entry_type_for_controller_action" do
    let(:routes) do
      [
        { route_path: "work_orders/export_pdf", route_comment: "匯出", entry_type: "pdf" },
      ]
    end

    it "returns matched route entry type" do
      entry_type = service.entry_type_for_controller_action(routes, "pms/work_orders", "export_pdf")

      expect(entry_type).to eq("pdf")
    end

    it "falls back to action name inference" do
      entry_type = service.entry_type_for_controller_action([], "", "export_pdf")

      expect(entry_type).to eq("pdf")
    end

    it "falls back to page when no match" do
      entry_type = service.entry_type_for_controller_action([], "pms/work_orders", "index")

      expect(entry_type).to eq("page")
    end
  end
end
