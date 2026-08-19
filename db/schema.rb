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

ActiveRecord::Schema[7.1].define(version: 2026_08_18_120012) do
  create_table "business_features", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "business_module_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "domain_action"
    t.text "description"
    t.integer "position"
    t.integer "source", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_module_id", "slug"], name: "index_business_features_on_business_module_id_and_slug", unique: true
    t.index ["business_module_id"], name: "index_business_features_on_business_module_id"
    t.index ["project_id"], name: "index_business_features_on_project_id"
  end

  create_table "business_modules", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.integer "position"
    t.integer "source", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "slug"], name: "index_business_modules_on_project_id_and_slug", unique: true
    t.index ["project_id"], name: "index_business_modules_on_project_id"
  end

  create_table "changed_code_entities", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "pull_request_analysis_id", null: false
    t.bigint "changed_file_id", null: false
    t.bigint "code_entity_id"
    t.integer "entity_type", null: false
    t.string "class_name"
    t.string "method_name"
    t.integer "change_kind", null: false
    t.boolean "validation_changed", default: false, null: false
    t.boolean "association_changed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["changed_file_id"], name: "index_changed_code_entities_on_changed_file_id"
    t.index ["code_entity_id"], name: "index_changed_code_entities_on_code_entity_id"
    t.index ["pull_request_analysis_id"], name: "index_changed_code_entities_on_pull_request_analysis_id"
  end

  create_table "changed_files", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "pull_request_analysis_id", null: false
    t.string "file_path", null: false
    t.string "previous_file_path"
    t.integer "change_type", null: false
    t.integer "additions", default: 0, null: false
    t.integer "deletions", default: 0, null: false
    t.text "patch"
    t.boolean "binary", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_analysis_id", "file_path"], name: "index_changed_files_on_pull_request_analysis_id_and_file_path", unique: true
    t.index ["pull_request_analysis_id"], name: "index_changed_files_on_pull_request_analysis_id"
  end

  create_table "code_entities", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.integer "entity_type", null: false
    t.string "name", null: false
    t.string "class_name"
    t.string "method_name"
    t.string "file_path", null: false
    t.integer "line_start"
    t.integer "line_end"
    t.string "namespace"
    t.string "signature_hash", null: false
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "entity_type"], name: "index_code_entities_on_project_id_and_entity_type"
    t.index ["project_id", "file_path"], name: "index_code_entities_on_project_id_and_file_path"
    t.index ["project_id", "signature_hash"], name: "index_code_entities_on_project_id_and_signature_hash", unique: true
    t.index ["project_id"], name: "index_code_entities_on_project_id"
  end

  create_table "feature_code_entities", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "business_feature_id", null: false
    t.bigint "code_entity_id", null: false
    t.integer "role"
    t.integer "source", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_feature_id", "code_entity_id"], name: "index_feature_code_entities_on_feature_and_entity", unique: true
    t.index ["business_feature_id"], name: "index_feature_code_entities_on_business_feature_id"
    t.index ["code_entity_id"], name: "index_feature_code_entities_on_code_entity_id"
  end

  create_table "graphify_artifacts", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "pull_request_analysis_id", null: false
    t.string "format", null: false
    t.text "raw_content"
    t.json "parsed_content"
    t.string "graphify_version"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_analysis_id", "format"], name: "idx_on_pull_request_analysis_id_format_cf5afa30e0"
    t.index ["pull_request_analysis_id"], name: "index_graphify_artifacts_on_pull_request_analysis_id"
  end

  create_table "impact_items", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "pull_request_analysis_id", null: false
    t.bigint "business_feature_id"
    t.bigint "code_entity_id"
    t.bigint "source_changed_code_entity_id"
    t.integer "impact_level", null: false
    t.text "reason"
    t.json "evidence"
    t.boolean "needs_manual_review", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_feature_id"], name: "index_impact_items_on_business_feature_id"
    t.index ["code_entity_id"], name: "index_impact_items_on_code_entity_id"
    t.index ["impact_level"], name: "index_impact_items_on_impact_level"
    t.index ["pull_request_analysis_id"], name: "index_impact_items_on_pull_request_analysis_id"
    t.index ["source_changed_code_entity_id"], name: "index_impact_items_on_source_changed_code_entity_id"
  end

  create_table "projects", charset: "utf8mb4", force: :cascade do |t|
    t.string "owner", null: false
    t.string "repository_name", null: false
    t.string "github_full_name", null: false
    t.string "default_branch"
    t.string "repository_path"
    t.string "base_sha"
    t.string "last_synced_sha"
    t.datetime "last_synced_at"
    t.integer "status", default: 0, null: false
    t.integer "analysis_status", default: 0, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_full_name"], name: "index_projects_on_github_full_name", unique: true
    t.index ["status"], name: "index_projects_on_status"
  end

  create_table "pull_request_analyses", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.integer "pr_number", null: false
    t.string "pr_title"
    t.text "pr_description"
    t.string "pr_author"
    t.string "base_branch"
    t.string "base_sha"
    t.string "head_branch"
    t.string "head_sha"
    t.string "merge_base_sha"
    t.integer "status", default: 0, null: false
    t.text "error_message"
    t.string "error_stage"
    t.string "workspace_path"
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "pr_number"], name: "index_pull_request_analyses_on_project_id_and_pr_number"
    t.index ["project_id"], name: "index_pull_request_analyses_on_project_id"
  end

  create_table "solid_queue_blocked_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", charset: "utf8mb4", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", charset: "utf8mb4", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", charset: "utf8mb4", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", charset: "utf8mb4", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", charset: "utf8mb4", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "test_cases", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "test_report_id", null: false
    t.bigint "business_feature_id"
    t.bigint "impact_item_id"
    t.integer "case_type", null: false
    t.integer "position", null: false
    t.string "name", null: false
    t.string "page_path"
    t.text "verification_purpose"
    t.json "steps"
    t.text "expected_result"
    t.text "failure_criteria"
    t.text "notes"
    t.json "evidence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_feature_id"], name: "index_test_cases_on_business_feature_id"
    t.index ["impact_item_id"], name: "index_test_cases_on_impact_item_id"
    t.index ["test_report_id"], name: "index_test_cases_on_test_report_id"
  end

  create_table "test_reports", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "pull_request_analysis_id", null: false
    t.string "title"
    t.text "summary"
    t.text "markdown_content"
    t.json "structured_content", null: false
    t.integer "status", default: 0, null: false
    t.text "error_message"
    t.string "generated_by"
    t.string "llm_provider"
    t.string "model_name"
    t.string "prompt_version", null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_analysis_id", "created_at"], name: "index_test_reports_on_pull_request_analysis_id_and_created_at"
    t.index ["pull_request_analysis_id"], name: "index_test_reports_on_pull_request_analysis_id"
  end

  add_foreign_key "business_features", "business_modules"
  add_foreign_key "business_features", "projects"
  add_foreign_key "business_modules", "projects"
  add_foreign_key "changed_code_entities", "changed_files"
  add_foreign_key "changed_code_entities", "code_entities"
  add_foreign_key "changed_code_entities", "pull_request_analyses"
  add_foreign_key "changed_files", "pull_request_analyses"
  add_foreign_key "code_entities", "projects"
  add_foreign_key "feature_code_entities", "business_features"
  add_foreign_key "feature_code_entities", "code_entities"
  add_foreign_key "graphify_artifacts", "pull_request_analyses"
  add_foreign_key "impact_items", "business_features"
  add_foreign_key "impact_items", "changed_code_entities", column: "source_changed_code_entity_id"
  add_foreign_key "impact_items", "code_entities"
  add_foreign_key "impact_items", "pull_request_analyses"
  add_foreign_key "pull_request_analyses", "projects"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "test_cases", "business_features"
  add_foreign_key "test_cases", "impact_items"
  add_foreign_key "test_cases", "test_reports"
  add_foreign_key "test_reports", "pull_request_analyses"
end
