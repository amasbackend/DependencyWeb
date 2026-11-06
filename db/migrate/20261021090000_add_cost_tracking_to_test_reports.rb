class AddCostTrackingToTestReports < ActiveRecord::Migration[7.1]
  def change
    add_column :test_reports, :cached_input_tokens, :integer
    # Token count × unit price at generation time (Llm::Pricing), stored so a
    # later price change doesn't rewrite what past reports cost.
    add_column :test_reports, :estimated_cost_usd, :decimal, precision: 12, scale: 6
    # Snapshot of the unit prices / exchange rate the estimate used.
    add_column :test_reports, :pricing, :json
  end
end
