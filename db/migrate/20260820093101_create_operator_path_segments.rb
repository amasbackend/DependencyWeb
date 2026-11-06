class CreateOperatorPathSegments < ActiveRecord::Migration[7.1]
  def change
    create_table :operator_path_segments do |t|
      t.references :operator_path, null: false, foreign_key: true
      t.references :code_entity, foreign_key: true
      t.integer :position, null: false
      t.string :label, null: false
      t.integer :evidence_kind, null: false
      t.json :evidence_ref

      t.timestamps
    end

    add_index :operator_path_segments, [ :operator_path_id, :position ], unique: true
  end
end
