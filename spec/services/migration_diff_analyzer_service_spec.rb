# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationDiffAnalyzerService do
  subject(:service) { described_class.new }

  it "parses add_column from migration patch" do
    patch = <<~PATCH
      @@ -1,5 +1,6 @@
      +    add_column :work_orders, :estimated_hours, :decimal
    PATCH

    impacts = service.analyze_patch(patch)

    expect(impacts.size).to eq(1)
    expect(impacts.first).to include(
      table: "work_orders",
      column: "estimated_hours",
      change_type: "add_column",
      model_name: "WorkOrder",
    )
  end

  it "parses other column change types" do
    patch = <<~PATCH
      +    change_column :work_orders, :estimated_hours, :integer
      +    remove_column :work_orders, :legacy_field
      +    rename_column :work_orders, :old_name, :new_name
    PATCH

    impacts = service.analyze_patch(patch)

    expect(impacts.pluck(:change_type)).to contain_exactly("change_column", "remove_column", "rename_column")
  end

  it "analyzes file entries" do
    impacts = service.analyze_file(
      filename: "db/migrate/20260101000000_add_hours.rb",
      patch: "+    add_column :work_orders, :estimated_hours, :decimal",
    )

    expect(impacts.first[:column]).to eq("estimated_hours")
  end

  it "returns empty array for blank patch" do
    expect(service.analyze_patch(nil)).to eq([])
  end
end
