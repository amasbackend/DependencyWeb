class CreateTestCases < ActiveRecord::Migration[7.1]
  def change
    create_table :test_cases do |t|
      t.references :test_report, null: false, foreign_key: true
      t.references :business_feature, foreign_key: true
      t.references :impact_item, foreign_key: true
      t.integer :case_type, null: false
      t.integer :position, null: false
      t.string :name, null: false
      t.string :page_path
      t.text :verification_purpose
      t.json :steps
      t.text :expected_result
      t.text :failure_criteria
      t.text :notes
      t.json :evidence

      t.timestamps
    end
  end
end
