class CreateRelateModel < ActiveRecord::Migration[7.1]
  def change
    create_table :relate_models do |t|
      t.references :management_page, foreign_key: { to_table: :management_pages }
      t.references :action_page, foreign_key: { to_table: :action_pages }
      t.string :name
      t.json :select_column
      t.json :modify_column
      t.json :delete_column
      t.timestamps
    end
  end
end
