class CreateManagementPage < ActiveRecord::Migration[7.1]
  def change
    create_table :management_pages do |t|
      t.references :company, foreign_key: { to_table: :companies }
      t.string :name
      t.timestamps
    end
  end
end
