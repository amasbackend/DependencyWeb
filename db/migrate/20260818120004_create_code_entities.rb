class CreateCodeEntities < ActiveRecord::Migration[7.1]
  def change
    create_table :code_entities do |t|
      t.references :project, null: false, foreign_key: true
      t.integer :entity_type, null: false
      t.string :name, null: false
      t.string :class_name
      t.string :method_name
      t.string :file_path, null: false
      t.integer :line_start
      t.integer :line_end
      t.string :namespace
      t.string :signature_hash, null: false
      t.json :metadata

      t.timestamps
    end

    add_index :code_entities, [ :project_id, :signature_hash ], unique: true
    add_index :code_entities, [ :project_id, :entity_type ]
    add_index :code_entities, [ :project_id, :file_path ]
  end
end
