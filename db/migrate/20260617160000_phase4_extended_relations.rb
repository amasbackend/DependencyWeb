# frozen_string_literal: true

class Phase4ExtendedRelations < ActiveRecord::Migration[7.1]
  def change
    change_table :action_pages, bulk: true do |t|
      t.boolean :has_spec, default: false, null: false
      t.json :blueprint_names
      t.json :related_files
    end

    create_table :shared_concerns do |t|
      t.references :company, null: false, foreign_key: true
      t.references :action_page, null: false, foreign_key: true
      t.string :concern_name, null: false
      t.string :concern_file_path

      t.timestamps
    end

    add_index :shared_concerns, %i[company_id concern_name], name: "index_shared_concerns_on_company_id_and_concern_name"
    add_index :shared_concerns, %i[action_page_id concern_name], unique: true,
              name: "index_shared_concerns_on_action_page_id_and_concern_name"
  end
end
