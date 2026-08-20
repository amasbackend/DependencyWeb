class RenameTestReportsModelName < ActiveRecord::Migration[7.1]
  # `model_name` collides with ActiveModel::Naming's own class method
  # (every ActiveRecord model responds to `.model_name` for form/route
  # helpers) — Rails refuses to define an attribute method with the same
  # name: "model_name is defined by Active Record". Went undetected since
  # Phase 1 because nothing wrote to this column until Phase 12
  # (Llm::AnalyzeTestScope) actually created a TestReport row.
  def change
    rename_column :test_reports, :model_name, :llm_model
  end
end
