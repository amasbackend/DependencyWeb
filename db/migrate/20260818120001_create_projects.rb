class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects do |t|
      t.string :owner, null: false
      t.string :repository_name, null: false
      t.string :github_full_name, null: false
      t.string :default_branch
      t.string :repository_path
      t.string :base_sha
      t.string :last_synced_sha
      t.datetime :last_synced_at
      t.integer :status, null: false, default: 0
      t.integer :analysis_status, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :projects, :github_full_name, unique: true
    add_index :projects, :status
  end
end
