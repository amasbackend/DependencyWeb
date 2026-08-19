class CreateBusinessModules < ActiveRecord::Migration[7.1]
  def change
    create_table :business_modules do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :position
      t.integer :source, null: false, default: 0

      t.timestamps
    end

    add_index :business_modules, [ :project_id, :slug ], unique: true
  end
end
