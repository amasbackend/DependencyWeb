class AddChangedFlagToActionPagesAndRelateModels < ActiveRecord::Migration[7.1]
  def change
    add_column :action_pages, :changed_flag, :boolean, default: false, null: false
    add_column :relate_models, :changed_flag, :boolean, default: false, null: false

    add_index :action_pages, :changed_flag
    add_index :relate_models, :changed_flag
  end
end
