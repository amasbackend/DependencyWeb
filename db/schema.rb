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

ActiveRecord::Schema[7.1].define(version: 2026_07_14_153000) do
  create_table "action_pages", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id"
    t.bigint "management_page_id"
    t.string "name"
    t.json "relate_action"
    t.json "relate_model"
    t.json "select_column"
    t.json "modify_column"
    t.json "delete_column"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "changed_flag", default: false, null: false
    t.string "operation_type"
    t.string "display_label"
    t.json "play_chain"
    t.string "source_file_path"
    t.string "channel", default: "web", null: false
    t.boolean "has_spec", default: false, null: false
    t.json "blueprint_names"
    t.json "related_files"
    t.index ["changed_flag"], name: "index_action_pages_on_changed_flag"
    t.index ["company_id"], name: "index_action_pages_on_company_id"
    t.index ["management_page_id"], name: "index_action_pages_on_management_page_id"
  end

  create_table "companies", charset: "utf8mb4", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "github_owner"
    t.string "github_branch", default: "master", null: false
    t.datetime "last_synced_at"
  end

  create_table "entry_points", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "action_page_id"
    t.bigint "ui_menu_id"
    t.string "controller_path"
    t.string "controller_action"
    t.string "http_method"
    t.string "route_path"
    t.string "route_comment"
    t.string "perm_module"
    t.string "perm_action"
    t.string "channel", default: "web", null: false
    t.string "entry_type", default: "page", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_page_id"], name: "index_entry_points_on_action_page_id"
    t.index ["company_id", "controller_path", "controller_action"], name: "index_entry_points_on_company_controller_action"
    t.index ["company_id"], name: "index_entry_points_on_company_id"
    t.index ["ui_menu_id"], name: "index_entry_points_on_ui_menu_id"
  end

  create_table "impact_records", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.integer "pr_number", null: false
    t.string "source_type", null: false
    t.string "source_name", null: false
    t.string "source_file_path"
    t.string "target_type", null: false
    t.bigint "target_id", null: false
    t.string "impact_level", null: false
    t.string "reason"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "pr_number"], name: "index_impact_records_on_company_id_and_pr_number"
    t.index ["company_id"], name: "index_impact_records_on_company_id"
    t.index ["impact_level"], name: "index_impact_records_on_impact_level"
    t.index ["target_type", "target_id"], name: "index_impact_records_on_target_type_and_target_id"
  end

  create_table "locale_metadata", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "locale", default: "zh-TW", null: false
    t.json "model_labels"
    t.json "attribute_labels"
    t.json "perm_module_labels"
    t.json "state_labels"
    t.datetime "imported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "perm_action_labels"
    t.json "operation_type_labels"
    t.json "menu_labels"
    t.index ["company_id"], name: "index_locale_metadata_on_company_id", unique: true
  end

  create_table "management_pages", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_management_pages_on_company_id"
  end

  create_table "pr_analyses", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.integer "pr_number", null: false
    t.json "analysis_input"
    t.json "impact_summary"
    t.json "qa_report"
    t.json "tech_report"
    t.datetime "analyzed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "pr_number"], name: "index_pr_analyses_on_company_id_and_pr_number", unique: true
    t.index ["company_id"], name: "index_pr_analyses_on_company_id"
  end

  create_table "relate_models", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "management_page_id"
    t.bigint "action_page_id"
    t.string "name"
    t.json "select_column"
    t.json "modify_column"
    t.json "delete_column"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "changed_flag", default: false, null: false
    t.index ["action_page_id"], name: "index_relate_models_on_action_page_id"
    t.index ["changed_flag"], name: "index_relate_models_on_changed_flag"
    t.index ["management_page_id"], name: "index_relate_models_on_management_page_id"
  end

  create_table "shared_concerns", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "action_page_id", null: false
    t.string "concern_name", null: false
    t.string "concern_file_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_page_id", "concern_name"], name: "index_shared_concerns_on_action_page_id_and_concern_name", unique: true
    t.index ["action_page_id"], name: "index_shared_concerns_on_action_page_id"
    t.index ["company_id", "concern_name"], name: "index_shared_concerns_on_company_id_and_concern_name"
    t.index ["company_id"], name: "index_shared_concerns_on_company_id"
  end

  create_table "ui_menus", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "namespace", default: "", null: false
    t.string "menu_label", null: false
    t.string "module_label"
    t.string "controller_path", null: false
    t.json "actions"
    t.string "perm_module"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_ui_menus_on_company_id"
  end

  add_foreign_key "action_pages", "companies"
  add_foreign_key "action_pages", "management_pages"
  add_foreign_key "entry_points", "action_pages"
  add_foreign_key "entry_points", "companies"
  add_foreign_key "entry_points", "ui_menus"
  add_foreign_key "impact_records", "companies"
  add_foreign_key "locale_metadata", "companies"
  add_foreign_key "management_pages", "companies"
  add_foreign_key "pr_analyses", "companies"
  add_foreign_key "relate_models", "action_pages"
  add_foreign_key "relate_models", "management_pages"
  add_foreign_key "shared_concerns", "action_pages"
  add_foreign_key "shared_concerns", "companies"
  add_foreign_key "ui_menus", "companies"
end
