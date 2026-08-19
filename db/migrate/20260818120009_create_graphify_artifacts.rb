class CreateGraphifyArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :graphify_artifacts do |t|
      t.references :pull_request_analysis, null: false, foreign_key: true
      t.string :format, null: false
      t.text :raw_content
      t.json :parsed_content
      t.string :graphify_version
      t.datetime :generated_at

      t.timestamps
    end

    add_index :graphify_artifacts, [ :pull_request_analysis_id, :format ]
  end
end
