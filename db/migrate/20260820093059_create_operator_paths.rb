class CreateOperatorPaths < ActiveRecord::Migration[7.1]
  def change
    create_table :operator_paths do |t|
      t.references :business_feature, null: false, foreign_key: true, index: { unique: true }
      t.integer :confidence_source, null: false, default: 0
      t.boolean :needs_manual_review, null: false, default: false
      t.datetime :resolved_at

      t.timestamps
    end
  end
end
