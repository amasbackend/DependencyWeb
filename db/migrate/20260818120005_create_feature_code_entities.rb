class CreateFeatureCodeEntities < ActiveRecord::Migration[7.1]
  def change
    create_table :feature_code_entities do |t|
      t.references :business_feature, null: false, foreign_key: true
      t.references :code_entity, null: false, foreign_key: true
      t.integer :role
      t.integer :source, null: false, default: 0

      t.timestamps
    end

    add_index :feature_code_entities, [ :business_feature_id, :code_entity_id ], unique: true, name: "index_feature_code_entities_on_feature_and_entity"
  end
end
