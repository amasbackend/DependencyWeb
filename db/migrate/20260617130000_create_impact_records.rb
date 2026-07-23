# frozen_string_literal: true

class CreateImpactRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :impact_records do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :pr_number, null: false
      t.string :source_type, null: false
      t.string :source_name, null: false
      t.string :source_file_path
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :impact_level, null: false
      t.string :reason
      t.json :metadata

      t.timestamps
    end

    add_index :impact_records, %i[company_id pr_number]
    add_index :impact_records, %i[target_type target_id]
    add_index :impact_records, :impact_level
  end
end
