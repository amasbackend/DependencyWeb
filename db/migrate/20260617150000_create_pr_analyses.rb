# frozen_string_literal: true

class CreatePrAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :pr_analyses do |t|
      t.references :company, null: false, foreign_key: true
      t.integer :pr_number, null: false
      t.json :analysis_input
      t.json :impact_summary
      t.json :qa_report
      t.json :tech_report
      t.datetime :analyzed_at

      t.timestamps
    end

    add_index :pr_analyses, %i[company_id pr_number], unique: true, name: "index_pr_analyses_on_company_id_and_pr_number"
  end
end
