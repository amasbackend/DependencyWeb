# frozen_string_literal: true

require "rails_helper"

RSpec.describe ControllerActorParserService do
  subject(:service) { described_class.new }

  let(:web_controller) do
    <<~RUBY
      class Pms::WorkOrdersController < ApplicationController
        before_action -> { permission_check("work_order", "edit") }, only: [:create]

        def create
          WorkOrder::Create.call!(params: work_order_params)
        end

        def export_pdf
          WorkOrder::ExportPdf.result!(work_order: @work_order)
        end

        def _hidden
        end
      end
    RUBY
  end

  let(:api_controller) do
    <<~RUBY
      class Api::StartWorkOrdersController < ApplicationController
        def create
          Api::StartWorkOrder.call!
        end
      end
    RUBY
  end

  it "maps controller actions to actor calls with permissions" do
    entries = service.parse_file(
      web_controller,
      file_path: "app/controllers/pms/work_orders_controller.rb",
    )

    create_entry = entries.find { |e| e[:controller_action] == "create" }
    export_entry = entries.find { |e| e[:controller_action] == "export_pdf" }

    expect(create_entry).to include(
      controller_path: "pms/work_orders",
      actor_name: "WorkOrder::Create",
      perm_module: "work_order",
      perm_action: "edit",
      channel: "web",
      entry_type: "page",
    )
    expect(export_entry[:entry_type]).to eq("export")
    expect(entries.map { |e| e[:controller_action] }).not_to include("_hidden")
  end

  it "marks API controllers with api channel" do
    entries = service.parse_file(
      api_controller,
      file_path: "app/controllers/api/start_work_orders_controller.rb",
    )

    expect(entries.first).to include(
      controller_path: "api/start_work_orders",
      actor_name: "Api::StartWorkOrder",
      channel: "api",
    )
  end

  it "uses default permission when action is not listed in only" do
    content = <<~RUBY
      class Pms::WorkOrdersController < ApplicationController
        before_action -> { permission_check("work_order", "read") }

        def index
          WorkOrder::List.call!
        end
      end
    RUBY

    entries = service.parse_file(content, file_path: "app/controllers/pms/work_orders_controller.rb")

    expect(entries.first[:perm_module]).to eq("work_order")
    expect(entries.first[:perm_action]).to eq("read")
  end
end
