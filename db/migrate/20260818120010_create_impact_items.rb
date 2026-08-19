class CreateImpactItems < ActiveRecord::Migration[7.1]
  def change
    create_table :impact_items do |t|
      t.references :pull_request_analysis, null: false, foreign_key: true
      t.references :business_feature, foreign_key: true
      t.references :code_entity, foreign_key: true
      t.references :source_changed_code_entity, foreign_key: { to_table: :changed_code_entities }
      t.integer :impact_level, null: false
      t.text :reason
      t.json :evidence
      t.boolean :needs_manual_review, null: false, default: false

      t.timestamps
    end

    add_index :impact_items, :impact_level
  end
end
