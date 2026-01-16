# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 20_241_126_000_004) do
  create_table 'action_pages', charset: 'utf8mb4', force: :cascade do |t|
    t.bigint 'company_id'
    t.bigint 'management_page_id'
    t.string 'name'
    t.json 'relate_action'
    t.json 'relate_model'
    t.json 'select_column'
    t.json 'modify_column'
    t.json 'delete_column'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'changed_flag', default: false, null: false
    t.index ['changed_flag'], name: 'index_action_pages_on_changed_flag'
    t.index ['company_id'], name: 'index_action_pages_on_company_id'
    t.index ['management_page_id'], name: 'index_action_pages_on_management_page_id'
  end

  create_table 'companies', charset: 'utf8mb4', force: :cascade do |t|
    t.string 'name'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end

  create_table 'management_pages', charset: 'utf8mb4', force: :cascade do |t|
    t.bigint 'company_id'
    t.string 'name'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['company_id'], name: 'index_management_pages_on_company_id'
  end

  create_table 'relate_models', charset: 'utf8mb4', force: :cascade do |t|
    t.bigint 'management_page_id'
    t.bigint 'action_page_id'
    t.string 'name'
    t.json 'select_column'
    t.json 'modify_column'
    t.json 'delete_column'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.boolean 'changed_flag', default: false, null: false
    t.index ['action_page_id'], name: 'index_relate_models_on_action_page_id'
    t.index ['changed_flag'], name: 'index_relate_models_on_changed_flag'
    t.index ['management_page_id'], name: 'index_relate_models_on_management_page_id'
  end

  add_foreign_key 'action_pages', 'companies'
  add_foreign_key 'action_pages', 'management_pages'
  add_foreign_key 'management_pages', 'companies'
  add_foreign_key 'relate_models', 'action_pages'
  add_foreign_key 'relate_models', 'management_pages'
end
