class AddEvidenceHashAndTemperatureToTestReports < ActiveRecord::Migration[7.1]
  def change
    add_column :test_reports, :evidence_hash, :string
    add_column :test_reports, :temperature, :float
  end
end
