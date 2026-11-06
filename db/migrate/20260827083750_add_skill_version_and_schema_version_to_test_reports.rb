class AddSkillVersionAndSchemaVersionToTestReports < ActiveRecord::Migration[7.1]
  def change
    add_column :test_reports, :skill_version, :string
    add_column :test_reports, :schema_version, :string
  end
end
