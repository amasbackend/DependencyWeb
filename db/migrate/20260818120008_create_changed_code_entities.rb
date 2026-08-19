class CreateChangedCodeEntities < ActiveRecord::Migration[7.1]
  def change
    create_table :changed_code_entities do |t|
      t.references :pull_request_analysis, null: false, foreign_key: true
      t.references :changed_file, null: false, foreign_key: true
      t.references :code_entity, foreign_key: true
      t.integer :entity_type, null: false
      t.string :class_name
      t.string :method_name
      t.integer :change_kind, null: false
      t.boolean :validation_changed, null: false, default: false
      t.boolean :association_changed, null: false, default: false

      t.timestamps
    end
  end
end
