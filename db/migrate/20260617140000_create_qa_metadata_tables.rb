# frozen_string_literal: true

class CreateQaMetadataTables < ActiveRecord::Migration[7.1]
  def change
    create_table :ui_menus do |t|
      t.references :company, null: false, foreign_key: true
      t.string :namespace, null: false, default: ""
      t.string :menu_label, null: false
      t.string :module_label
      t.string :controller_path, null: false
      t.json :actions
      t.string :perm_module

      t.timestamps
    end

    create_table :locale_metadata do |t|
      t.references :company, null: false, foreign_key: true, index: { unique: true }
      t.string :locale, null: false, default: "zh-TW"
      t.json :model_labels
      t.json :attribute_labels
      t.json :perm_module_labels
      t.json :state_labels
      t.datetime :imported_at

      t.timestamps
    end

    create_table :entry_points do |t|
      t.references :company, null: false, foreign_key: true
      t.references :action_page, foreign_key: true
      t.references :ui_menu, foreign_key: true
      t.string :controller_path
      t.string :controller_action
      t.string :http_method
      t.string :route_path
      t.string :route_comment
      t.string :perm_module
      t.string :perm_action
      t.string :channel, null: false, default: "web"
      t.string :entry_type, null: false, default: "page"

      t.timestamps
    end

    add_index :entry_points, %i[company_id controller_path controller_action],
              name: "index_entry_points_on_company_controller_action"

    change_table :action_pages, bulk: true do |t|
      t.string :operation_type
      t.string :display_label
      t.json :play_chain
      t.string :source_file_path
      t.string :channel, null: false, default: "web"
    end
  end
end
