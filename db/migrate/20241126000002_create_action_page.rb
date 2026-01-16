class CreateActionPage < ActiveRecord::Migration[7.1]
  def change
    create_table :action_pages do |t|
      t.references :company, foreign_key: { to_table: :companies }
      t.references :management_page, foreign_key: { to_table: :management_pages }
      t.string :name
      t.json :relate_action
      t.json :relate_model
      t.json :select_column
      t.json :modify_column
      t.json :delete_column
      t.timestamps
    end
  end
end
