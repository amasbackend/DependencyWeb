# PR 牽連範圍與測試報告 — 重構規劃文件

> **專案**：RelateDoc（關聯文件管理系統）  
> **版本**：v1.1  
> **建立日期**：2026-06-17  
> **狀態**：規劃中

---

## 1. 背景與目標

### 1.1 現況摘要

系統已能從 GitHub 匯入 Rails 專案的 **Management Page → Action Page → Relate Model** 靜態關聯圖，並在 PR 分析時以 `changed_flag` 標記直接變更的 Actor / Model。  
已支援 **GitHub 母資料同步**（`SyncFromGithub`），可從 master 等分支重新匯入比對基準。

### 1.2 核心問題

| 問題 | 說明 |
|------|------|
| 僅直接命中 | PR 改了 Actor A，呼叫 A 的 Actor B 不會被標記 |
| Model 下游未傳播 | Model 變更時，使用該 Model 的 ActionPage 不會被標記 |
| 單一 boolean 標記 | 無法區分直接/間接影響、無法說明牽連原因 |
| 檔案類型過窄 | 僅掃描 `app/actors/**`、`app/models/**` |
| 無結構化報告 | QA 無法取得「必測 / 建議迴歸 / 欄位影響」清單 |
| **前端僅技術名稱** | 只顯示 `WorkOrder::Create`、`Component`，QA 無法對應實際選單與操作 |
| **Actor 資料夾 ≠ UI 功能** | `work_order` 同時服務工單管理、排程、API 等多個選單，現有分組誤導 QA |
| **母專案 metadata 未利用** | `locales`、`routes` 註解、`_navbar`、controller 等已有中文與路徑資訊，匯入時未擷取 |

### 1.3 重構目標

1. **圖傳播分析**：利用 `relate_action`、`relate_model` 及 **play 鏈** 做上下游牽連計算
2. **分級影響記錄**：取代單一 `changed_flag`，記錄影響等級與原因
3. **QA 業務視圖**：以「功能選單路徑 + 操作類型 + 中文欄位」呈現，技術視圖可切換
4. **母專案 metadata 匯入**：匯入時擷取 locales / routes / navbar / controller / 權限等
5. **測試範圍報告**：產出 QA 測試清單（JSON / Markdown），支援必測 / 建議迴歸 / 欄位影響
6. **擴大關聯捕獲**：巢狀 Actor、API/Web 分流、Concern、Blueprint、狀態機、PDF 匯出路徑等
7. **擴大 PR 掃描**：controller、migration、routes 等變更納入影響分析
8. **（選用）CI 整合**：GitHub PR Comment / Check Run 自動回饋

### 1.4 參考母專案（target/PrjJieZhou）

| 項目 | 現況 | 重構運用 |
|------|------|---------|
| `app/actors/` | 15 個模組資料夾 | Management Page 來源（既有） |
| `app/controllers/` | 21 個 | **高優先**：Controller → Actor 對照 |
| `config/routes.rb` | 含中文註解 | **高優先**：路由功能說明 |
| `views/**/_navbar.html.erb` | 選單名稱 ↔ controller | **高優先**：QA 功能路徑 |
| `locales/zh-TW/model.yml` | Model/欄位/perm_module 中文 | **高優先**：業務視圖標籤 |
| `permission_check(...)` | 權限模組與動作 | **高優先**：測試帳號準備 |
| `play OtherActor` | Actor 呼叫鏈 | **高優先**：比字串比對更準的傳播 |
| `app/actors/api/` | 機台 API Actor | **中優先**：API 與 Web 分流 |
| `Material::Price::List` 等 | 巢狀 Actor | **中優先**：補強關聯漏抓 |
| `app/blueprints/` | API 回應結構 | **中優先** |
| `actors/concerns/` | 共用邏輯 | **中優先**：多 Actor 連帶影響 |
| `spec/actors/` | 僅 2 個 spec | **中優先**：標示無自動測試覆蓋 |

### 1.5 非目標（本階段不做）

- 完整 AST / Ruby Parser 靜態分析（如 `parser` gem 全專案掃描）
- 自動執行測試或產生測試程式碼
- 多 PR 比對、跨分支 diff
- 使用者認證與權限系統
- Vue 元件內部邏輯的深度靜態分析（僅捕獲路徑與檔名級關聯）

---

## 2. 關聯捕獲功能矩陣

### 2.1 高優先度（母專案已有資料，匯入階段擷取）

| # | 捕獲項目 | 資料來源 | 儲存位置（建議） | 主要用途 |
|---|---------|---------|-----------------|---------|
| H1 | Controller → Actor | `app/controllers/**/*.rb` | `entry_points` | 「哪個頁面動作」對應哪個 Actor |
| H2 | Route → 功能說明 | `config/routes.rb` 行尾註解 | `entry_points.route_comment` | QA 操作說明（新增工單、開始加工） |
| H3 | 選單 → Controller | `views/**/_navbar.html.erb` | `ui_menus` | QA 功能路徑（PMS > 工單管理） |
| H4 | 權限模組 | `permission_check("work_order", "edit")` | `entry_points.perm_module`, `perm_action` | 測試帳號權限準備 |
| H5 | Model / 欄位中文名 | `locales/zh-TW/model.yml` | `locale_metadata`（JSON 快取於 company） | 欄位顯示、測試資料準備 |
| H6 | perm_module 中文 | `model.yml` → `perm_module` | `ui_menus.module_label` | 「生產管理」「品保檢驗管理」 |
| H7 | Actor play 鏈 | `play :step, OtherActor` | `action_pages.play_chain`（JSON） | 傳播分析、流程提示 |

### 2.2 中優先度（需額外解析，PR 分析與匯入皆可用）

| # | 捕獲項目 | 資料來源 | 儲存位置（建議） | 主要用途 |
|---|---------|---------|-----------------|---------|
| M1 | 巢狀 Actor | `Material::Price::List` 等 | `action_pages`（擴充 name 支援） | 補強非第一層 actors 漏抓 |
| M2 | API 與 Web 分流 | `app/actors/api/*` + API controller | `entry_points.channel`（web/api） | 區分機台 API vs 網頁測試 |
| M3 | Blueprint | `app/blueprints/**` | `related_files` | API 回傳欄位影響 |
| M4 | Concern 共用邏輯 | `app/actors/concerns/**` | `shared_concerns` | 一處改動、多 Actor 受影響 |
| M5 | Vue 前端 | `app/packs/src/**` | `related_files`（frontend） | 表單 UI 測試範圍提示 |
| M6 | 狀態機 | `locales` 的 `state` / model enum | `locale_metadata.states` | 流程狀態轉換測試 |
| M7 | PDF / 匯出 | `export_pdf`, `show_pdf` routes | `entry_points.entry_type`（export/pdf） | 常被遺漏的測試路徑 |
| M8 | Spec 覆蓋 | `spec/actors/**` | `action_pages.has_spec` | 標示無自動測試覆蓋 |

### 2.3 QA 呈現增強（依賴 H1–H7 資料）

| 項目 | 說明 |
|------|------|
| 業務視圖 / 技術視圖 | 預設業務視圖給 QA；開發可切換技術視圖 |
| 操作類型標籤 | 從 Actor 後綴推斷：Create→新增、List→查詢、Export*→匯出 |
| 欄位中英對照 | `cnc_machine_id` → 設備名稱（hover 顯示英文） |
| 依選單分組 | 取代僅依 actor 資料夾分組 |
| PR 測試清單 | 必測 / 建議迴歸 / 無 spec 覆蓋，可勾選匯出 |

---

## 3. 現有架構與目標架構

### 3.1 現況（PR 分析）

```
GithubAnalysisService#analyze_changes
  ├── analyze_actor_changes  → 僅 app/actors/*.rb
  └── analyze_model_changes  → 僅 app/models/*.rb
           ↓
FlagUpdateService → changed_flag 直接比對 name
           ↓
UI 顯示 Actor / Model 技術名稱
```

### 3.2 目標（匯入 + PR 分析 + QA 呈現）

```
【匯入階段】CodeAnalysis::RelationsFromGithub（擴充）
  ├── 既有：Actor / Model 靜態關聯
  ├── Phase 2：MetadataImportService（H1–H7）
  └── Phase 4：ExtendedRelationService（M1–M8）
           ↓
【PR 分析】GithubAnalysisService + ImpactAnalysisService
  ├── 檔案分類 + patch 解析
  ├── 圖傳播（relate_action + play_chain + concern）
  └── impact_records 分級寫入
           ↓
【報告】TestScopeReportService
  ├── 技術報告（Actor / Model）
  └── QA 報告（選單路徑 / 中文欄位 / 測試清單）
           ↓
【UI】業務視圖 + 技術視圖 + 報告匯出
```

---

## 4. 修改範圍總覽

### 4.1 資料庫

| 項目 | 階段 | 類型 | 說明 |
|------|------|------|------|
| `impact_records` | Phase 1 | **新增** | PR 影響記錄主表 |
| `pr_analyses` | Phase 3 | **新增** | PR 分析快照 |
| `ui_menus` | Phase 2 | **新增** | 選單 / 模組 / perm 中文標籤 |
| `entry_points` | Phase 2 | **新增** | Controller action ↔ Actor ↔ Route |
| `locale_metadata` | Phase 2 | **新增** | 以 company 為單位的 YAML 快取 |
| `shared_concerns` | Phase 4 | **新增** | Concern ↔ Actor 多對多 |
| `action_pages` 擴充欄位 | Phase 2 | **修改** | 見下方 |
| `companies` 擴充 | 已完成 | **修改** | `github_branch`, `last_synced_at` |
| `changed_flag` | 全階段 | **保留** | 向下相容 |

#### `impact_records`（Phase 1）

```ruby
create_table :impact_records do |t|
  t.references :company, null: false, foreign_key: true
  t.integer    :pr_number, null: false
  t.string     :source_type, null: false    # actor | model | controller | concern | migration | route | file
  t.string     :source_name, null: false
  t.string     :source_file_path
  t.string     :target_type, null: false     # action_page | relate_model | entry_point | ui_menu
  t.bigint     :target_id
  t.string     :impact_level, null: false   # direct | caller | callee | model_consumer | play_chain | concern
  t.string     :reason
  t.json       :metadata
  t.timestamps
end
```

#### `ui_menus`（Phase 2）

```ruby
create_table :ui_menus do |t|
  t.references :company, null: false, foreign_key: true
  t.string     :namespace, null: false       # pms | setting | estimate | api
  t.string     :menu_label, null: false       # 工單管理
  t.string     :module_label                  # 生產管理（來自 perm_module）
  t.string     :controller_path, null: false # pms/work_orders
  t.json       :actions                      # %w[index new create]
  t.string     :perm_module
  t.timestamps
end
```

#### `entry_points`（Phase 2）

```ruby
create_table :entry_points do |t|
  t.references :company, null: false, foreign_key: true
  t.references :action_page, foreign_key: true
  t.references :ui_menu, foreign_key: true
  t.string     :controller_path
  t.string     :controller_action
  t.string     :http_method
  t.string     :route_path
  t.string     :route_comment               # routes.rb 中文註解
  t.string     :perm_module
  t.string     :perm_action
  t.string     :channel, default: "web"      # web | api
  t.string     :entry_type, default: "page"  # page | api | export | pdf
  t.timestamps
end
```

#### `action_pages` 擴充欄位（Phase 2–4）

```ruby
add_column :action_pages, :operation_type, :string      # create | update | list | export ...
add_column :action_pages, :display_label, :string       # 新增工單（推斷或來自 route）
add_column :action_pages, :play_chain, :json
add_column :action_pages, :source_file_path, :string    # app/actors/work_order/create.rb
add_column :action_pages, :has_spec, :boolean, default: false
add_column :action_pages, :channel, :string, default: "web"  # web | api
```

#### `locale_metadata`（Phase 2）

```ruby
create_table :locale_metadata do |t|
  t.references :company, null: false, foreign_key: true
  t.string     :locale, default: "zh-TW"
  t.json       :model_labels                 # { "WorkOrder" => "工單" }
  t.json       :attribute_labels             # { "work_order" => { "cnc_machine_id" => "設備名稱" } }
  t.json       :perm_module_labels
  t.json       :state_labels
  t.datetime   :imported_at
  t.timestamps
end
```

---

### 4.2 後端程式（依模組）

#### 新增檔案

| 檔案路徑 | 階段 | 職責 |
|----------|------|------|
| `app/models/impact_record.rb` | P1 | 影響記錄 |
| `app/models/pr_analysis.rb` | P3 | PR 分析快照 |
| `app/models/ui_menu.rb` | P2 | 選單 metadata |
| `app/models/entry_point.rb` | P2 | 入口點 metadata |
| `app/models/locale_metadata.rb` | P2 | i18n 快取 |
| `app/models/shared_concern.rb` | P4 | Concern 關聯 |
| `app/services/dependency_graph_service.rb` | P1 | 依賴圖 |
| `app/services/impact_analysis_service.rb` | P1 | 圖傳播 |
| `app/services/metadata_import_service.rb` | P2 | H1–H7 匯入編排 |
| `app/services/locale_parser_service.rb` | P2 | 解析 model.yml |
| `app/services/navbar_parser_service.rb` | P2 | 解析 _navbar |
| `app/services/route_parser_service.rb` | P2 | 解析 routes.rb |
| `app/services/controller_actor_parser_service.rb` | P2 | H1 + H4 |
| `app/services/play_chain_parser_service.rb` | P2 | H7 |
| `app/services/operation_type_inferer_service.rb` | P2 | Actor 後綴 → 操作類型 |
| `app/services/test_scope_report_service.rb` | P3 | QA + 技術報告 |
| `app/services/extended_relation_service.rb` | P4 | M1–M8 |
| `app/services/pr_file_classifier_service.rb` | P3 | PR 檔案分類 |
| `app/services/migration_diff_analyzer_service.rb` | P3 | migration 欄位 |
| `app/actors/code_analysis/import_metadata.rb` | P2 | 匯入流程掛鉤 |
| `app/actors/github_analysis/analyze_pr_impact.rb` | P1 | PR 分析編排 |
| `app/actors/github_analysis/generate_test_scope_report.rb` | P3 | 報告編排 |
| `app/helpers/qa_display_helper.rb` | P2 | 業務視圖格式化 |
| `spec/services/*_spec.rb` | 各階段 | 見 §7 |

#### 修改檔案

| 檔案路徑 | 階段 | 修改內容 |
|----------|------|----------|
| `app/actors/code_analysis/relations_from_github.rb` | P2 | 匯入後呼叫 `ImportMetadata` |
| `app/actors/code_analysis/analyze_action_page.rb` | P2 | 擷取 play_chain、source_file_path |
| `app/actors/code_analysis/import_to_database.rb` | P2 | 寫入擴充欄位、關聯 entry_points |
| `app/services/flag_update_service.rb` | P1 | 委派 ImpactAnalysisService |
| `app/services/github_analysis_service.rb` | P3 | 檔案分類、concern、controller |
| `app/controllers/management_pages_controller.rb` | P2–P3 | `test_scope_report`、view_mode 參數 |
| `app/views/management_pages/show.html.erb` | P2–P3 | 業務/技術視圖、測試清單 |
| `config/routes.rb` | P1–P3 | 新 API |
| `lib/tasks/github_analysis.rake` | P3 | 報告 task |
| `lib/tasks/code_analysis.rake` | P2 | metadata 匯入選項 |
| `README.md` | 各階段 | 操作說明 |

---

### 4.3 前端 / UI

| 區塊 | 階段 | 變更 |
|------|------|------|
| 視圖切換 | P2 | 「業務視圖」/「技術視圖」Toggle |
| 表格欄位 | P2 | 功能路徑、操作類型、中文欄位、權限、URL |
| 分組方式 | P2 | 依 `ui_menus` 選單分組（可切回 actor 資料夾） |
| PR 影響 | P1 | `impact_level` 標籤 |
| 測試清單 | P3 | 必測 / 建議迴歸 / 無 spec，Markdown 匯出 |
| 通道標記 | P4 | Web / API 圖示分流 |

---

### 4.4 API 路由

```ruby
resources :management_pages, only: %i[index show] do
  member do
    post :reset_flags
    post :update_flags_from_pr
    post :sync_from_github              # 已完成
    get  :get_pr_info
    get  :test_scope_report             # ?pr_number=65&format=json|md|qa
  end
end
```

---

## 5. 分階段實作步驟

### Phase 1：圖傳播 + 分級影響

**目標**：解決 Actor 呼叫鏈與 Model 下游漏抓（PR 分析核心）。

| 步驟 | 工作項目 | 產出 |
|------|----------|------|
| 1.1 | 建立 `impact_records` migration 與 Model | DB 就緒 |
| 1.2 | 實作 `DependencyGraphService` | caller/callee/model 消費圖 |
| 1.3 | 實作 `ImpactAnalysisService#propagate` | 分級影響列表 |
| 1.4 | 重構 `FlagUpdateService` | 寫入 impact_records + 同步 changed_flag |
| 1.5 | 修改 `GithubAnalysis::UpdateFlags` | 回傳 impact_summary |
| 1.6 | 單元測試 + 手動 PR 比對 | 見 §7.1 Phase 1 |

#### 傳播演算法

```
輸入：direct_actors, direct_models（來自 PR 變更檔案）

1. direct Actor → ActionPage impact_level: direct
2. 向上：relate_action 含 A → caller（depth 可設 2）
3. 向下：A 的 relate_model → callee
4. direct Model → model_consumer + RelateModel direct
5. 衝突：direct > caller > model_consumer > caller_l2
6. 寫入 impact_records；同步 changed_flag
```

**預估工時**：3–5 人日

---

### Phase 2：高優先度 metadata 匯入 + QA 業務視圖

**目標**：匯入時擷取 H1–H7，前端以 QA 可讀方式呈現。

| 步驟 | 工作項目 | 對應 | 產出 |
|------|----------|------|------|
| 2.1 | DB：`ui_menus`, `entry_points`, `locale_metadata`, `action_pages` 擴充 | — | 表結構 |
| 2.2 | `LocaleParserService` | H5, H6 | model/attribute/perm 中文 |
| 2.3 | `NavbarParserService` | H3 | 選單 ↔ controller |
| 2.4 | `RouteParserService` | H2 | 路由註解 ↔ path |
| 2.5 | `ControllerActorParserService` | H1, H4 | controller#action ↔ Actor + 權限 |
| 2.6 | `PlayChainParserService` | H7 | play_chain JSON |
| 2.7 | `OperationTypeInfererService` | QA 呈現 | Create→新增 等 |
| 2.8 | `MetadataImportService` + `ImportMetadata` Actor | — | 掛入 sync/import 流程 |
| 2.9 | `QaDisplayHelper` + show 頁業務視圖 | QA 呈現 | 功能路徑、中文欄位 |
| 2.10 | 更新 `DependencyGraphService` | H7 | play_chain 納入傳播（可選） |

#### 業務視圖一列範例（目標）

```
模組：生產管理 > 工單管理
操作：新增工單（WorkOrder::Create）
權限：work_order / edit
涉及資料：工單、單零件、CNC機台
異動欄位：設備名稱、預計開始日期
入口：GET /pms/work_orders/new
```

**預估工時**：5–7 人日

---

### Phase 3：測試範圍報告 + PR 掃描擴充

**目標**：QA 測試清單匯出；PR 納入 controller / migration / routes。

| 步驟 | 工作項目 | 產出 |
|------|----------|------|
| 3.1 | 建立 `pr_analyses` 表 | 歷史 PR 可回溯 |
| 3.2 | `TestScopeReportService` | 技術報告 + **QA 報告**（`format=qa`） |
| 3.3 | `PrFileClassifierService` + 擴充 `GithubAnalysisService` | controller/migration/route 變更 |
| 3.4 | `MigrationDiffAnalyzerService` | 欄位級 `column_impacts` |
| 3.5 | Controller 變更 → entry_point → ActionPage 傳播 | 非 actor 檔 PR 也能標記 |
| 3.6 | API `test_scope_report` + UI 匯出 | Markdown 測試清單 |
| 3.7 | Rake `github_analysis:test_scope_report` | CLI 匯出 |

#### QA 報告 JSON 結構（擴充）

```json
{
  "pr_number": 65,
  "company": "PrjJieZhou",
  "view": "qa",
  "summary": { "must_test": 5, "suggested_regression": 12, "no_spec_coverage": 3 },
  "must_test": [
    {
      "menu_path": "生產管理 > 品保檢驗管理 > 編輯",
      "operation": "編輯",
      "action_page": "ExamineRecord::Update",
      "perm": "examine_record / edit",
      "affected_fields": ["檢驗日期", "量測數量", "結果"],
      "entry_url": "/pms/examine_records/:id/edit",
      "impact_level": "direct",
      "reason": "PR 直接修改 examine_record/update.rb"
    }
  ],
  "suggested_regression": [],
  "column_impacts": [],
  "uncovered_risks": [],
  "no_spec_coverage": ["ExamineRecord::KeyenceMeasurement"]
}
```

**預估工時**：4–6 人日

---

### Phase 4：中優先度關聯捕獲

**目標**：補強 M1–M8，降低漏抓與誤導。

| 步驟 | 工作項目 | 對應 | 產出 |
|------|----------|------|------|
| 4.1 | 巢狀 Actor 掃描 | M1 | 擴充 `CollectActionClassesFromGithub` 遞迴目錄 |
| 4.2 | API / Web channel 標記 | M2 | `action_pages.channel`, `entry_points.channel` |
| 4.3 | Blueprint 檔案關聯 | M3 | Actor 使用的 Blueprint 列表 |
| 4.4 | `shared_concerns` 表與解析 | M4 | Concern 變更 → 關聯 Actor 傳播 |
| 4.5 | 前端 packs 路徑記錄 | M5 | related_files（低信心提示） |
| 4.6 | 狀態標籤匯入 | M6 | locale state → 流程測試提示 |
| 4.7 | PDF/匯出 route 標記 | M7 | entry_type: export/pdf |
| 4.8 | Spec 掃描 | M8 | `has_spec` 欄位；報告 `no_spec_coverage` |
| 4.9 | PR 分析納入 concern / api / blueprint 變更 | M1–M4 | impact_records 擴充來源類型 |

**預估工時**：5–8 人日

---

### Phase 5：CI / GitHub 整合（選用）

| 步驟 | 工作項目 | 產出 |
|------|----------|------|
| 5.1 | GitHub Actions 觸發分析 | PR 自動產生報告 |
| 5.2 | PR Comment Bot | 貼 QA 測試清單 Markdown |
| 5.3 | Check Run | 顯示影響統計 |

**預估工時**：3–5 人日

---

## 6. 各階段驗證方式

### Phase 1 驗證

| 類型 | 驗證項目 | 通過標準 |
|------|---------|---------|
| 單元 | `DependencyGraphService` | 單層/雙層 caller、model_consumer、循環有深度上限 |
| 單元 | `ImpactAnalysisService` | direct 優先於 caller；合併不重複 |
| 整合 | 已知 PR（如 PrjJieZhou #65） | 重構後 flagged 數 **≥** 重構前；caller 有新增 |
| 手動 | UI `filter=changed` | 行為與先前相容 |
| 手動 | 重置 Flag | `impact_records` 一併清除 |
| 回歸 | `sync_from_github` | 不受影響 |

**驗證紀錄表（建議）**

| PR # | 重構前 direct | 重構後 direct | 新增 caller | 新增 model_consumer | 備註 |
|------|--------------|--------------|-------------|---------------------|------|
| | | | | | |

---

### Phase 2 驗證

| 類型 | 驗證項目 | 通過標準 |
|------|---------|---------|
| 單元 | `LocaleParserService` | `WorkOrder`→工單、`cnc_machine_id`→設備名稱 |
| 單元 | `NavbarParserService` | PrjJieZhou PMS navbar 解析出 4 個選單 |
| 單元 | `ControllerActorParserService` | `work_orders#create` ↔ `WorkOrder::Create` |
| 單元 | `PlayChainParserService` | `WorkOrder::Create` 含 `RefreshEstimatedCompletion` |
| 整合 | 執行 `companies:sync[PrjJieZhou]` | `ui_menus`、`entry_points`、`locale_metadata` 有資料 |
| 手動 | 業務視圖 | 不再只顯示 `work_order`；顯示「工單管理」等中文 |
| 手動 | 技術視圖切換 | 仍可見原始 Actor / Model 名稱 |
| 抽樣 | 5 筆 Action 人工對照 target 專案 | 功能路徑、權限與實際 controller 一致 |

**抽樣對照清單（PrjJieZhou 建議）**

| Actor | 預期選單 | 預期操作 | 預期權限 |
|-------|---------|---------|---------|
| `WorkOrder::Create` | 工單管理 | 新增 | work_order / edit |
| `ExamineRecord::Update` | 品保檢驗管理 | 編輯 | examine_record / edit |
| `Api::StartWorkOrder` | API | — | channel=api |

---

### Phase 3 驗證

| 類型 | 驗證項目 | 通過標準 |
|------|---------|---------|
| 單元 | `TestScopeReportService` | QA 報告含 menu_path、affected_fields |
| 單元 | `MigrationDiffAnalyzerService` | 正確解析 add_column |
| 整合 | `GET test_scope_report?format=qa` | 200 + 結構符合 §5 Phase 3 JSON |
| 手動 | QA 試讀 Markdown 報告 | 無需查 class 名即可知道測試範圍 |
| 手動 | PR 只改 controller | 對應 entry_point 被標記 |
| 手動 | PR 含 migration | `column_impacts` 有欄位中文名 |

---

### Phase 4 驗證

| 類型 | 驗證項目 | 通過標準 |
|------|---------|---------|
| 單元 | 巢狀 Actor 收集 | `Material::Price::List` 出現在 action_pages |
| 單元 | Concern 傳播 | 改 concern 檔 → 多個 Actor impact |
| 整合 | API Actor 分流 | `Api::*` channel=api |
| 手動 | Spec 標記 | 僅 2 個 spec 的 PrjJieZhou 正確標示 no_spec |
| 手動 | PDF 路由 | `export_pdf` 出現在 entry_type=pdf |

---

### Phase 5 驗證（選用）

| 類型 | 驗證項目 | 通過標準 |
|------|---------|---------|
| 整合 | 開測試 PR | Bot 自動留言含測試清單 |
| 手動 | 報告連結 | 可點回 RelateDoc 詳情頁 |

---

## 7. 測試計畫（自動化）

### 7.1 單元測試檔案

| 檔案 | 階段 |
|------|------|
| `spec/services/dependency_graph_service_spec.rb` | P1 |
| `spec/services/impact_analysis_service_spec.rb` | P1 |
| `spec/services/locale_parser_service_spec.rb` | P2 |
| `spec/services/navbar_parser_service_spec.rb` | P2 |
| `spec/services/route_parser_service_spec.rb` | P2 |
| `spec/services/controller_actor_parser_service_spec.rb` | P2 |
| `spec/services/play_chain_parser_service_spec.rb` | P2 |
| `spec/services/operation_type_inferer_service_spec.rb` | P2 |
| `spec/services/test_scope_report_service_spec.rb` | P3 |
| `spec/services/migration_diff_analyzer_service_spec.rb` | P3 |
| `spec/services/extended_relation_service_spec.rb` | P4 |

### 7.2 整合測試

- Fixture：以 `target/PrjJieZhou` 局部檔案建立 VCR 或 stub GitHub 回應
- `POST sync_from_github` → metadata 表有資料
- `POST update_flags_from_pr` → 回傳含 QA report 摘要
- `GET test_scope_report?format=qa` → 結構驗證

### 7.3 手動驗收（全階段）

1. `companies:sync[PrjJieZhou]` 後確認業務視圖可读
2. 選定 PR，比對重構前後影響範圍
3. 匯出 QA Markdown，交由 QA 填寫「是否足夠」回饋
4. 確認技術視圖、changed_flag 篩選、重置功能正常

---

## 8. 向下相容策略

| 項目 | 策略 |
|------|------|
| `changed_flag` | 保留；由 ImpactAnalysisService 同步 |
| 既有 UI 篩選 | `filter=changed` 不變 |
| 僅技術欄位舊資料 | 未 sync 前業務視圖 fallback 顯示英文 class 名 |
| `sync_from_github` | 同步時一併執行 MetadataImport（Phase 2 起） |
| 無 impact_records 舊 PR | 下次分析時建立 |

---

## 9. 風險與緩解

| 風險 | 影響 | 緩解 |
|------|------|------|
| `relate_action` 不完整 | 傳播漏抓 | play_chain 補強；定期 sync |
| Actor 資料夾 ≠ UI 選單 | QA 誤判 | 以 ui_menus 為業務視圖主分組 |
| navbar 為 ERB 非標準格式 | 解析失敗 | 支援 PrjJieZhou 格式；失敗時 fallback |
| 巢狀 Actor 掃描變慢 | 匯入時間增加 | 快取 GitHub 目錄列表 |
| Controller 正則誤判 | 錯誤 entry_point | 標示信心等級；人工覆寫 API（長期） |
| Concern / Vue 解析有限 | 漏抓 | 列入 uncovered_risks |
| GitHub API 限流 | sync 失敗 | 支援 target/ 本機解析（開發用，長期） |

---

## 10. 時程建議

| 階段 | 內容 | 建議週次 | 預估工時 | MVP |
|------|------|----------|----------|-----|
| **Phase 1** | 圖傳播 + impact_records | 第 1–2 週 | 3–5 人日 | ✅ |
| **Phase 2** | 高優先 metadata + 業務視圖 | 第 2–4 週 | 5–7 人日 | ✅ |
| **Phase 3** | QA 報告 + PR 掃描擴充 | 第 4–6 週 | 4–6 人日 | ✅ |
| **Phase 4** | 中優先關聯捕獲 | 第 6–8 週 | 5–8 人日 | |
| **Phase 5** | CI / GitHub 整合 | 視需求 | 3–5 人日 | |

**建議 MVP**：Phase 1 + 2 + 3（開發可看懂傳播、QA 可讀業務視圖與測試清單）。

**總預估**：20–31 人日（不含 Phase 5）。

---

## 11. 驗收標準

### Phase 1

- [ ] PR 分析後 caller / model_consumer 出現在 impact_records
- [ ] 每筆影響有 impact_level 與 reason
- [ ] changed_flag 篩選正常；重置清除 impact_records

### Phase 2（高優先 H1–H7）

- [ ] sync 後 ui_menus、entry_points、locale_metadata 有資料
- [ ] 業務視圖顯示選單路徑、操作類型、欄位中文名
- [ ] 技術視圖可切換且資料完整
- [ ] play_chain 寫入 action_pages
- [ ] PrjJieZhou 抽樣 5 筆人工對照通過

### Phase 3

- [ ] `format=qa` 報告含 menu_path、affected_fields、perm
- [ ] controller / migration PR 能標記影響
- [ ] Markdown 測試清單可匯出

### Phase 4（中優先 M1–M8）

- [ ] 巢狀 Actor、API channel、concern 傳播可用
- [ ] has_spec / no_spec_coverage 正確
- [ ] PDF/匯出 entry_type 標記

### Phase 5（選用）

- [ ] PR 自動留言測試清單

---

## 12. 附錄：實作檢查清單

### Phase 1

```
[ ] db/migrate/create_impact_records.rb
[ ] app/models/impact_record.rb
[ ] app/services/dependency_graph_service.rb
[ ] app/services/impact_analysis_service.rb
[ ] app/services/flag_update_service.rb — 重構
[ ] app/actors/github_analysis/analyze_pr_impact.rb
[ ] spec/services/impact_analysis_service_spec.rb
```

### Phase 2（高優先）

```
[ ] db/migrate/create_ui_menus.rb
[ ] db/migrate/create_entry_points.rb
[ ] db/migrate/create_locale_metadata.rb
[ ] db/migrate/add_qa_fields_to_action_pages.rb
[ ] app/services/metadata_import_service.rb
[ ] app/services/locale_parser_service.rb
[ ] app/services/navbar_parser_service.rb
[ ] app/services/route_parser_service.rb
[ ] app/services/controller_actor_parser_service.rb
[ ] app/services/play_chain_parser_service.rb
[ ] app/actors/code_analysis/import_metadata.rb
[ ] app/helpers/qa_display_helper.rb
[ ] app/views/management_pages/show.html.erb — 業務視圖
[ ] spec/services/*_parser_service_spec.rb
```

### Phase 3

```
[ ] db/migrate/create_pr_analyses.rb
[ ] app/services/test_scope_report_service.rb
[ ] app/services/pr_file_classifier_service.rb
[ ] app/services/migration_diff_analyzer_service.rb
[ ] GET test_scope_report（format=qa）
[ ] lib/tasks/github_analysis.rake — test_scope_report
```

### Phase 4（中優先）

```
[ ] db/migrate/create_shared_concerns.rb
[ ] app/services/extended_relation_service.rb
[ ] CollectActionClassesFromGithub — 巢狀掃描
[ ] Spec 掃描 → has_spec
[ ] Concern PR 傳播
[ ] spec/services/extended_relation_service_spec.rb
```

---

## 13. 修訂紀錄

| 版本 | 日期 | 說明 |
|------|------|------|
| v1.0 | 2026-06-17 | 初版：PR 牽連分析與測試報告 |
| v1.1 | 2026-06-17 | 納入高/中優先關聯捕獲、QA 業務視圖、PrjJieZhou 對照、分階段驗證方式；階段調整為 Phase 1–5 |
