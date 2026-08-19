class CreateBusinessFeatures < ActiveRecord::Migration[7.1]
  def change
    create_table :business_features do |t|
      t.references :project, null: false, foreign_key: true
      t.references :business_module, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :domain_action
      t.text :description
      t.integer :position
      t.integer :source, null: false, default: 0

      t.timestamps
    end

    add_index :business_features, [ :business_module_id, :slug ], unique: true
  end
end
