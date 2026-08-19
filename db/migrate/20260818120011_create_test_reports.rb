class CreateTestReports < ActiveRecord::Migration[7.1]
  def change
    create_table :test_reports do |t|
      t.references :pull_request_analysis, null: false, foreign_key: true
      t.string :title
      t.text :summary
      t.text :markdown_content
      t.json :structured_content, null: false
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.string :generated_by
      t.string :llm_provider
      t.string :model_name
      t.string :prompt_version, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :duration_ms

      t.timestamps
    end

    add_index :test_reports, [ :pull_request_analysis_id, :created_at ]
  end
end
