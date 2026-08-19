class CreatePullRequestAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :pull_request_analyses do |t|
      t.references :project, null: false, foreign_key: true
      t.integer :pr_number, null: false
      t.string :pr_title
      t.text :pr_description
      t.string :pr_author
      t.string :base_branch
      t.string :base_sha
      t.string :head_branch
      t.string :head_sha
      t.string :merge_base_sha
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.string :error_stage
      t.string :workspace_path
      t.integer :retry_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :pull_request_analyses, [ :project_id, :pr_number ]
  end
end
