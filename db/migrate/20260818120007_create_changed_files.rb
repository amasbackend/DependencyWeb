class CreateChangedFiles < ActiveRecord::Migration[7.1]
  def change
    create_table :changed_files do |t|
      t.references :pull_request_analysis, null: false, foreign_key: true
      t.string :file_path, null: false
      t.string :previous_file_path
      t.integer :change_type, null: false
      t.integer :additions, null: false, default: 0
      t.integer :deletions, null: false, default: 0
      t.text :patch
      t.boolean :binary, null: false, default: false

      t.timestamps
    end

    add_index :changed_files, [ :pull_request_analysis_id, :file_path ], unique: true
  end
end
