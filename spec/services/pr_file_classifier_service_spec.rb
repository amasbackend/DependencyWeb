# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrFileClassifierService do
  subject(:service) { described_class.new }

  it "classifies common Rails paths" do
    expect(service.classify_filename("app/actors/work_order/create.rb")).to eq("actor")
    expect(service.classify_filename("app/models/work_order.rb")).to eq("model")
    expect(service.classify_filename("app/controllers/pms/work_orders_controller.rb")).to eq("controller")
    expect(service.classify_filename("db/migrate/20260101000000_add_field.rb")).to eq("migration")
    expect(service.classify_filename("config/routes.rb")).to eq("route")
    expect(service.classify_filename("app/blueprints/work_order/info_blueprint.rb")).to eq("blueprint")
    expect(service.classify_filename("app/actors/concerns/work_order_helper.rb")).to eq("concern")
    expect(service.classify_filename("README.md")).to eq("other")
  end

  it "groups files by category" do
    grouped = service.classify_files([
                                       { "filename" => "app/actors/work_order/create.rb", "status" => "modified" },
                                       { "filename" => "app/models/work_order.rb", "status" => "added" },
                                     ])

    expect(grouped["actor"].size).to eq(1)
    expect(grouped["model"].first[:status]).to eq("added")
  end

  it "extracts controller path" do
    path = service.controller_path_from_file("app/controllers/pms/work_orders_controller.rb")
    expect(path).to eq("pms/work_orders")
    expect(service.controller_path_from_file("README.md")).to be_nil
  end

  it "accepts plain filename strings" do
    grouped = service.classify_files(["README.md"])

    expect(grouped["other"].first[:filename]).to eq("README.md")
    expect(grouped["other"].first[:status]).to eq("modified")
  end
end
