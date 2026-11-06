# 前端重構與跨 LLM 一致性架構計畫

> 本文件依 `docs/frontend_plan.md`（81 節任務指令）要求產出，完成後停止，不進行任何程式碼修改，等待下一步實作指令。
>
> 標註方式：每節重要結論後以 `[C]`=從程式碼確認、`[R]`=設計建議、`[V]`=需實作時驗證 標記，方便日後追蹤哪些是既定事實、哪些是決策、哪些仍需驗證。

---

## 1. Current State（現況）

### 1.1 Frontend Stack `[C]`

| 項目 | 現況 |
|---|---|
| Rails | 7.1.6 / Ruby 3.1.4 |
| Asset Pipeline | **Sprockets**（`gem "sprockets-rails"`），非 Propshaft |
| JS | **importmap-rails 2.2.3**，無 Node/bundler/`package.json`，`config/importmap.rb` 只 pin `application`/`@hotwired/turbo-rails`/`@hotwired/stimulus`/`@hotwired/stimulus-loading` |
| Hotwire | `turbo-rails` 2.0.23、`stimulus-rails` 1.3.4 已安裝，但**幾乎未使用**——僅 `app/javascript/controllers/hello_controller.js`（生成器預設樣板，未被任何 view 引用） |
| CSS 框架 | 無。`app/assets/stylesheets/application.css` 是未修改的 Sprockets manifest stub（`require_tree .`），**全站零自訂 CSS 規則** |
| 元件框架 | 無 ViewComponent gem，無 `app/components/` |
| 圖形/視覺化套件 | 無（grep cytoscape/d3/sigma/vis.js/mermaid 全部零命中） |

### 1.2 Layout `[C]`

`app/views/layouts/application.html.erb`（17 行）：純 stock 生成器內容，僅 `csrf_meta_tags`/`csp_meta_tag`/`stylesheet_link_tag`/`javascript_importmap_tags` + `yield`。**無 header/nav/footer partial，無 flash 訊息渲染**。

### 1.3 Views 逐頁對照 `[C]`

| 頁面 | 檔案 | 現況呈現方式 |
|---|---|---|
| 首頁 | `app/views/home/index.html.erb` | GitHub 匯入表單（`form_with` + `<details>` 折疊 Advanced Option）+ 專案列表 `<ul><li>`（無 partial） |
| Project Detail | `app/views/projects/show.html.erb` | 專案資訊 `<p>` 標籤；業務/技術視圖切換靠 `?view=` query param + `link_to class: "active"`（無對應 CSS）；Business Module/Feature 巢狀 `<div><strong><ul><li>` |
| PR Analysis | `app/views/projects/pull_request_analyses/show.html.erb` | 狀態區塊 `<p>`；`<details>` 顯示 PR metadata；6-tab nav 迴圈 `Projects::PullRequestAnalysesController::TABS`；依 `?tab=` render `tabs/_*.html.erb` |
| ├ 測試範圍 | `tabs/_test_scope.html.erb` | 報告標題/摘要、markdown 下載連結、`<details><pre>` 完整 markdown、測試案例依 `case_type` 分組 `<h3>/<h4>/<ol>` |
| ├ 修改內容 | `tabs/_changes.html.erb` | changed_files 與 changed_code_entities 各為 `<ul><li>` |
| ├ 業務視圖 | `tabs/_business.html.erb` | impact_items 依 `risk_level` 分組，`<h3>+<ul><li>`，`<details>`「可能影響原因」 |
| ├ 技術視圖 | `tabs/_technical.html.erb` | changed entities 依 entity_type 分組，impact_items 依 impact_level 分組 |
| ├ Graphify | `tabs/_graphify.html.erb` | `artifact.raw_content` 直接塞進 `<pre>`（**無圖形視覺化**） |
| └ Raw Diff | `tabs/_raw_diff.html.erb` | `file.patch` 直接塞進 `<pre>`（**無語法高亮/行號**） |

全站僅 6 個 partial（皆為上述 6 個 tab），無 BusinessFeature 專屬 index/show view（功能永遠只在 `projects/show` 與 PR tab 內嵌顯示）。

### 1.4 LLM Architecture `[C]`

已存在且真正運作：`Llm::Provider` factory（`app/services/llm/provider.rb`，依 `LLM_PROVIDER` env var 切換 Claude/Gemini/OpenAI）、單一共用 `Llm::TestScopePrompt`、`Llm::TestScopeInputBuilder`（deterministic evidence 組裝）、`Llm::TestScopeSchema`（手寫驗證器，擋 persist）、`Reports::Build`/`Reports::RenderMarkdown`（純 Ruby、與 LLM 解耦的報告渲染）。詳見第 9 節。

---

## 2. Problem Map（逐頁問題與改善方向）

| 頁面 | 現在怎麼呈現 | 問題 | 預計如何改善 |
|---|---|---|---|
| 首頁 | 匯入表單常駐佔版面 + `<ul>` 專案列表 | 無 Dashboard 摘要、無法快速掃描、狀態無視覺提示 | Project Dashboard 頂部統計卡 + Data Table + 匯入表單收進 Modal/Drawer（Phase 2） |
| Project Detail | 資訊 `<p>` 堆疊、Business/Technical 巢狀 `<ul>` | 資訊階層不明顯、大量功能無法掃描、無搜尋/篩選 UI | Table 化 + 第二層 Navigation（Overview/業務功能/技術實體/PR 分析/Graphify IDE）+ Expandable Row（Phase 3） |
| Business Feature | 純文字巢狀列表，無操作路徑 | 操作人員不知道「去哪裡點」，只有技術欄位 | Data Table，預設只顯示模組/功能/操作路徑/狀態，技術細節收進 Expand（Phase 3-4） |
| Technical View | 巢狀 `<ul>`，Direct/Indirect 用文字分組 | 難以掃描依賴關係、無法點擊追蹤到 Graphify | Table + 點擊可直接定位 Graphify IDE（Phase 5） |
| PR Analysis | 6-tab，資訊骨架良好但視覺扁平 | PR Header 無視覺層級、Branch Warning 只是文字、測試案例非表格 | 保留 6-tab 結構，Header 卡片化、Warning 改 Alert、測試案例 Table 化（Phase 6） |
| Graphify | `raw_content` 直接塞 `<pre>` | 不是最終使用者應看到的 UX，只有工程師看得懂 | 三欄 Graphify IDE（Explorer/Canvas/Inspector），Raw JSON 移至 Advanced（Phase 8） |
| Raw Diff | `file.patch` 塞 `<pre>` | 無語法高亮、行號、無法快速跳檔案 | 逐行渲染 Diff Viewer，複用既有 `GitDiffParser`（Phase 7） |

第四節列的 16 項問題經逐項核對，**全數成立**（詳見第 1 節現況與上表）。

---

## 3. Information Architecture

```text
/                                          首頁（Project Dashboard）
/projects/:id                              Project Overview
  ?view=business                           業務功能（Data Table）
  ?view=technical                          技術實體（Data Table）
/projects/:id/pull_request_analyses/:id    PR Analysis
  ?tab=test_scope   （預設）                測試範圍
  ?tab=changes                             修改內容
  ?tab=business                            業務視圖
  ?tab=technical                           技術視圖
  ?tab=graphify                            Graphify（三欄 IDE 或 raw fallback）
  ?tab=raw_diff                            Raw Diff Viewer
/projects/:id/graph                        Graphify IDE（獨立頁，新路由）`[R]`
```

`[C]` 現況只有 9 條路由，`business_modules`/`business_features`/`graphify` 皆無獨立路由，一切靠 `projects#show` 的 `?view=` 與 PR 頁的 `?tab=` 承載——本 IA 延續此 query-param 慣例（保留 URL 可分享/可重整/可返回），只新增 Graphify IDE 專屬路由（因為需要獨立的 node-detail Turbo Frame fetch 端點，見第 8 節）。`[R]`

第二層 Navigation（Project Detail 頁內）：Overview / 業務功能 / 技術實體 / PR 分析 / Graphify IDE — 對應現有 `?view=` 機制擴充，不需要新的 router namespace。`[R]`

---

## 4. Design System

採用 **`tailwindcss-rails`**（Tailwind v4），理由與具體做法見第 8.5 節「與姊妹專案 DependencyWeb 的比較」。以下為 token 與元件規劃：

### 4.1 Design Token（Tailwind v4 `@theme`，寫在 `app/assets/tailwind/application.css`）`[R]`

```css
@import "tailwindcss";

@theme {
  --color-risk-high: ...;    /* 對齊既有 ImpactItem::RISK_LABEL 高風險 */
  --color-risk-medium: ...;  /* 中風險 */
  --color-risk-low: ...;     /* 低風險 */
  --color-status-ready: ...;      /* Project#status ready */
  --color-status-failed: ...;     /* failed */
  --color-status-pending: ...;    /* pending/importing/syncing */
  --font-mono: ...;   /* SHA/Route/Class/File 一律用 monospace */
}
```

Risk 色彩必須對齊 `app/models/impact_item.rb` 已定義的 `RISK_LABEL`/`RISK_ORDER`（高風險/中風險/低風險），不另創新詞彙。`[C]`（欄位已存在）`[R]`（色彩對應為設計建議）

### 4.2 Typography

Page Title / Section Title / Table Header / Body / Meta / Code / Badge 七層，SHA/Route/Class/File 用 `font-mono`（Tailwind `font-mono` utility）。`[R]`

### 4.3 Spacing

沿用 Tailwind 預設 4px 基準刻度（`p-1`=4px 起跳），不另建自訂 spacing scale，避免與 Tailwind 內建刻度衝突產生兩套系統。`[R]`

### 4.4 元件（Table / Button / Badge / Tabs / Tooltip / Expandable Row / Panel / Code）

見第 6 節 Component Plan，統一原則：**重複樣式一律抽成 partial 或 helper，禁止 class 字串複製貼上**（見第 8.5 節，這是與姊妹專案 DependencyWeb 唯一刻意的差異）。`[R]`

---

## 5. Page Wireframes（ASCII）

### Homepage
```
┌────────────────────────────────────────────────────────┐
│ GitHub PR 測試範圍分析              [＋ 匯入 GitHub 專案] │
│ 專案總數 6   Ready 5   分析中 0   Failed 1               │
├────────────────────────────────────────────────────────┤
│ 專案            母分支  Base SHA  功能數 Graphify 狀態 ⋯  │
│ AMASTek/Prj...  master  5968f02   108    Ready    Ready  │
│  ⌄ (展開: Repository / Business Module 數 / 最近 PR ...) │
└────────────────────────────────────────────────────────┘
```

### Project Detail
```
┌────────────────────────────────────────────────────────┐
│ AMASTek / PrjJieZhou   master  Ready  Last Sync 08/19    │
│ [同步母分支] [分析 PR] [開啟 Graphify IDE]                │
├ Overview │ 業務功能 │ 技術實體 │ PR 分析 │ Graphify IDE ─┤
│ 模組   功能      操作人員路徑        Route          Graph │
│ CNC機台 CNC機台列表 系統設定→CNC機台   /setting/cnc...  12  │
└────────────────────────────────────────────────────────┘
```

### PR Analysis
```
┌────────────────────────────────────────────────────────┐
│ PR #113  Hotfix - 修正完成日計算方式 #5106    Completed  │
│ Base release3.1.3 → Head hotfix/...   2 檔案 1 實體 3 功能│
│ ⚠ Base Branch 不一致（若適用）                            │
├ 測試範圍│修改內容│業務視圖│技術視圖│Graphify│Raw Diff ────┤
│ 風險  模組 功能    操作路徑        驗證目的      類型      │
│ High  工單 預估完成日 PMS→工單→詳細 確認完成日計算 Direct  │
│  ▶ 為什麼需要測？（展開：Changed Actor/Graphify/證據）     │
└────────────────────────────────────────────────────────┘
```

### Graphify IDE
```
┌─────────────────────────────────────────────────────────┐
│ PrjJieZhou Graphify IDE                       Search      │
├ Explorer ────┬────────── Canvas ─────────┬─ Inspector ───┤
│ Business     │                           │ Node          │
│ Controller   │        [Cytoscape.js]     │ Type / File   │
│ Actor        │                           │ Dependencies  │
│ Model        │                           │               │
├──────────────┴───────────────────────────┴───────────────┤
│ Filters / Path / Selected Node    [Advanced: Raw JSON]    │
└─────────────────────────────────────────────────────────┘
```

### Raw Diff
```
┌────────────────────────────────────────────────────────┐
│ 2 Changed Files   ▾ app/actors/...(+7/-3)  ▸ spec/...    │
├────────────────────────────────────────────────────────┤
│  12 │   def total_production_speed                       │
│  13 │-    old_line                                        │
│  13 │+    new_line                                        │
└────────────────────────────────────────────────────────┘
```

以上為排版方向設計稿，實際視覺細節（間距/顏色/字重）於實作時依 Design System token 落地。`[R]`

---

## 6. Component Plan

| 元件 | 型態 | 職責 |
|---|---|---|
| `_header.html.erb` | Layout partial | 共用頂部區塊（目前 layout 完全沒有） |
| `status_badge(status)` | Helper | Project/PR/TestReport 狀態徽章，取代散落的文字 |
| `risk_badge(level)` | Helper | 對齊 `ImpactItem::RISK_LABEL` 的風險徽章 |
| `_data_table.html.erb` | Partial（+ block 或 locals） | 通用可排序/篩選表格骨架 |
| `disclosure_controller.js` | Stimulus | 在原生 `<details>` 的 `toggle` 事件上，首次展開才設定 Turbo Frame `src`（lazy load） |
| `tooltip_controller.js` | Stimulus | Hover 顯示操作路徑/技術資訊 tooltip（含鍵盤可達） |
| `sortable_controller.js` | Stimulus | 當頁表格客戶端排序 |
| `graph_controller.js` | Stimulus | 包裝 Cytoscape.js 實例，pan/zoom/hover/select，click 觸發 Inspector Turbo Frame |
| `_operator_path.html.erb` | Partial | 渲染 Operator Path breadcrumb（含「需要人工確認」狀態） |
| `_diff_file.html.erb` | Partial | 逐行 diff 渲染（複用 `GitDiffParser`） |
| `_graph_inspector.html.erb` | Partial（Turbo Frame） | Graphify IDE 右側節點詳情，伺服器渲染 |

不假設一定用 ViewComponent（`[C]` 現況未安裝該 gem，且姊妹專案 DependencyWeb 亦未採用）——採用 ERB Partial + Helper + Stimulus 的組合，理由見第 8.5 節。`[R]`

---

## 7. Operator Path Architecture

### 7.1 證據優先序（依實際可得訊號重新排序，非文件原始的 Navigation/Menu/Sidebar 序列）`[C]`+`[R]`

全域 grep 確認：此專案（含被分析的目標 repo）**完全沒有 Navigation/Menu/Sidebar/Breadcrumb 的結構化資料**可供讀取。改為：

1. **Route 註解**（`RoutesFileParser#comment`）— 已是 `BusinessFeatureNamer` 現有的最高優先訊號，直接複用 `[C]`
2. **目標 repo i18n controller/action key** — best-effort，非保證存在 `[R]`
3. **View 內 `button_to`/`link_to`/`submit_tag` 文字** — 全新掃描器，目前不存在 `[R]`，需新建
4. **CRUD 慣例樣板** — 複用 `BusinessFeatureNamer::CRUD_GROUPS` 模式 `[C]`
5. **裸 `Controller#Action`** — 最低信心，標記 `needs_manual_review: true`

若證據不足，一律顯示「**需要人工確認**」，禁止自行補一條看似合理但憑空的路徑——沿用 `_business.html.erb` 現有的 `needs_manual_review` 顯示模式。`[C]`

### 7.2 資料保存方式 `[R]`

```json
{
  "label": "CNC 機台列表",
  "evidence_kind": "route_comment_derived",
  "evidence_ref": {"file": "config/routes.rb", "line": 42, "comment": "CNC機台列表"},
  "code_entity_id": 123
}
```

兩張新表（設計，暫不寫 migration，見第 10 節）：
- `operator_paths`：`business_feature_id`、`confidence_source`、`needs_manual_review`、`resolved_at`
- `operator_path_segments`：`operator_path_id`、`position`、`label`、`evidence_kind`、`evidence_ref`（json）、`code_entity_id`

刻意不建通用 `graph_node`/`graph_edge`/`evidence_pack` 表——這些概念已被 `GraphifyArtifact#parsed_content` + `GraphifyGraphIndex` 的記憶體內圖遍歷完整覆蓋。`[C]`+`[R]`

### 7.3 解析服務 `[R]`

新增 `OperatorPathResolver`（模仿 `BusinessFeatureNamer` 的 `.call` pure-function 形狀）：走 `feature.feature_code_entities`（`[C]` 目前只有 `controller_action` role 被實際建立）找到 anchor `CodeEntity` → 依上述優先序解析 → 產出 `OperatorPath` + `OperatorPathSegment`。執行時機（build-time vs. 首次瀏覽 lazy resolve）留待實作時決定。`[V]`

---

## 8. Graphify IDE Architecture

### 8.1 Graph Data

來源：`GraphifyArtifact#parsed_content`（僅 `format: graph_json` 有值）`[C]`，遍歷引擎複用既有 `GraphifyGraphIndex`（reverse-BFS，depth 上限 5，每個判斷帶真實 edge chain）`[C]`，不重建平行的圖資料結構。

### 8.2 API

新增 `GET /projects/:project_id/pull_request_analyses/:id/graphify/nodes/:node_id`（或等效路由，命名依實作時 Rails 慣例調整）`[R]`，回傳 Turbo Frame 渲染的 Inspector 內容——伺服器渲染節點細節，不把完整資料重複塞進前端 JSON。

### 8.3 前端函式庫比較

| 條件 | Cytoscape.js | Sigma.js | D3 |
|---|---|---|---|
| 單檔 ESM，可直接 importmap pin | ✅ `cytoscape.esm.min.js` 自包含 | ❌ 需額外 pin `graphology` 及子套件，純 import map 環境版本協調脆弱 | ⚠️ 核心可以，但需另 pin `d3-force`/`d3-drag`/`d3-zoom` 才能組出圖形互動 |
| 內建 widget 互動（pan/zoom/select/hover） | ✅ | 部分 | ❌ 需手刻 |
| 與 `GraphifyGraphIndex` 的 depth 分層資料形狀相符的佈局 | ✅ `breadthfirst`/`concentric` | 較弱（多為 ForceAtlas2） | ⚠️ 只有 `d3-force`，力導向非深度分層，視覺上不match「影響隨深度擴散」 |

**選型：Cytoscape.js**，透過 `config/importmap.rb` pin CDN ESM build。`[R]`

```ruby
pin "cytoscape", to: "https://ga.jspm.io/npm:cytoscape@3.30.2/dist/cytoscape.esm.min.js"
```

### 8.4 Node Filter / Hover / Selection / Inspector / PR Overlay / Performance

- Hover：目前 Node 突出，直接 Parent/Child Highlight，其餘 opacity 降低（Cytoscape `cy.on('mouseover', 'node', ...)`）`[R]`
- Click：右側 Inspector 顯示（Turbo Frame，伺服器渲染，見 8.2）`[R]`
- PR Overlay：帶入 PR Analysis ID，Graph 上標示 Changed/Direct Impact/Indirect Impact/Unaffected 四種狀態（顏色來自 4.1 token）`[R]`
- Performance：**不一次 render 整份 graph.json**——初始只渲染 `direct_change` `ImpactItem` 周邊 N-hop 子圖（複用 `GraphifyGraphIndex` 既有 depth 上限機制），Explorer 側可再展開更大範圍 `[R]`，符合文件第七十二至七十三節「數千 Graph Nodes 不應一次 render」的要求

### 8.5 與姊妹專案 DependencyWeb 的比較（使用者明確指示參考）`[C]`

已實際稽核 `/home/micky/DependencyWeb`（同作者姊妹專案，`app/actors/` 慣例相同）：

- **真正在跑的樣式機制**：`tailwindcss-rails` gem（Tailwind v4）+ `bin/rails tailwindcss:watch`，透過 Sprockets `manifest.js` 的 `link_tree ../builds` 提供，**完全不依賴 JS bundler**——與 DependencyWeb2 現有 importmap-rails **完全相容**。
- `bootstrap-sass`/`sass-rails`/`@rails/webpacker`/`webpack`/`turbolinks` 皆**確認為死碼**（未接進 layout、未接進 `Procfile.dev`、程式碼零引用）——**不應複製**。
- 該專案**零元件抽象**：零 partial、零 helper、零 Stimulus，Tailwind class 字串在 4 個 view 逐一複製貼上（同組 button class 出現 8 次以上）——明確技術債，**不應原樣複製組織方式**。
- 該專案**無任何圖形視覺化**（grep cytoscape/d3/sigma/vis-network/mermaid/svg 全部零命中），Graphify IDE 選型無前例可循，維持 8.3 的獨立判斷。
- 該專案**無 Stimulus**，互動靠各 view 各自寫 vanilla JS + 手動 `turbo:load`/`turbo:before-cache` listener——DependencyWeb2 應用 Stimulus controller 取代這種各自為政的做法。

**結論**：DependencyWeb2 採用相同機制（`tailwindcss-rails`）但改善組織（抽出 partial/helper、用 Stimulus）——這是本計畫與姊妹專案唯一刻意的差異，寫入每個 Phase 的 acceptance criteria。

---

## 9. LLM Consistency Architecture

### 9.1 現況：比文件擔心的「三套各自生長」好很多 `[C]`

| 概念 | 狀態 | 位置 |
|---|---|---|
| Provider 抽象（Claude/Gemini/OpenAI） | **真實存在**，factory 運作正常 | `app/services/llm/provider.rb` + 3 個實作 |
| 共用 Prompt（非三套各自的 prompt） | **真實存在**，`TestScopePrompt` 三個 provider 共用同一份 | `app/services/llm/test_scope_prompt.rb` |
| 結構化 JSON Schema + Validator | **真實存在**，手寫 Ruby 驗證器，會擋 persist | `app/services/llm/test_scope_schema.rb` |
| Deterministic Evidence Input Builder | **真實存在**，但未持久化/無法 hash | `app/services/llm/test_scope_input_builder.rb` |
| Report Renderer 與 LLM 解耦 | **真實存在**，純 Ruby 模板 | `app/actors/reports/{build,render_markdown}.rb` |
| Canonical Skill 作為版本化檔案包（`skills/` 目錄） | **不存在**——只是一個 Ruby 常數 | — |
| skill_version/schema_version/evidence_hash/temperature | **不存在**——只有 `prompt_version` | — |
| 跨 Provider 一致性 regression test | **不存在**——現有測試只各自 stub 單一 vendor | — |
| Provider retry/timeout | **不存在**——失敗直接 raise，標記 `llm_failed` | — |

**結論：只做「補強」不做「重建」**——Evidence Builder → Canonical Skill → Provider Adapter → Structured Schema → Validator → Report Renderer 的管線已經是 provider-agnostic 的，不應重寫。

### 9.2 需新增的部分 `[R]`

1. **`skills/test_scope/{skill.md,input_schema.json,output_schema.json}`** — 外部化現有 `Llm::TestScopePrompt::SYSTEM_PROMPT`，不改變 runtime 行為，只是讓「一套 skill」的事實可見、可獨立版本化審閱。
2. **`test_reports` 新欄位**（設計階段，暫不寫 migration）：`skill_version`、`schema_version`、`evidence_hash`、`temperature`。
3. **`Llm::EvidenceHash`**（新 service）：對 `TestScopeInputBuilder` 的 deterministic 輸出做 SHA256，讓「同一份 evidence 送給不同 provider 的結果是否可比對」變得可行。
4. **三個 provider 補上可選 `temperature:` 參數**——`[C]` 目前三者皆未送出此參數，需個別加上 kwarg 傳遞，預設不設值以免無聲改變現有輸出行為。
5. **Provider 層有限重試**——僅針對網路/5xx，不對 `TestScopeSchema::ValidationError` 重試（避免用不同結果掩蓋模型輸出問題，模型輸出錯就應該照現有機制直接 `llm_failed`）。
6. **`test/services/llm/cross_provider_consistency_test.rb`**——固定 evidence fixture，同時 stub 三個 provider（走既有 Faraday stub 慣例），斷言三者輸出皆通過 `TestScopeSchema` 且 `evidence_hash` 一致。**這是目前唯一真正缺的一致性防線**。

### 9.3 一致性驗收原則（依文件第六十至六十一節）`[R]`

不要求文字完全相同（例如「確認預估完成日是否正確計算」vs.「驗證系統計算出的預估完成日期」可視為一致），但 Feature / Impact / Operator Path / Test Intent / Expected Result / Evidence 六項必須一致——`TestScopeSchema` 的驗證規則即是此一致性的技術落地。

---

## 10. Backend Changes

明確列出前端重構真正需要的後端改動，避免把需求塞給 Frontend view 自行臨時計算：

| 類型 | 項目 | 目的 |
|---|---|---|
| Model | `OperatorPath`、`OperatorPathSegment`（新） | 第 7 節 Operator Path |
| Model Enum | `operator_path_source_enum`（加入 `app/models/concerns/model_enum.rb`） | 比照既有 `business_entity_source_enum` 做法 |
| Service | `OperatorPathResolver`（新） | 解析證據鏈，模仿 `BusinessFeatureNamer` |
| Service | `Llm::EvidenceHash`（新） | 第 9 節 evidence_hash |
| Controller | 新 Graphify node-detail action（或 `GraphifyNodesController`） | 第 8 節 Inspector Turbo Frame |
| Controller | `ProjectsController#show` 加分頁 scope | 第 6 節 pagination |
| Controller | `Projects::PullRequestAnalysesController` 加 `impact_level` 篩選 param | Technical View 篩選 |
| Route | `config/routes.rb` 新增 Graphify node-detail 路由 | 第 8 節 |
| Migration（暫不執行，見下） | `operator_paths`、`operator_path_segments`、`test_reports` 加 4 欄 | 第 7、9 節 |

### 10.1 資料需求：目前已有 vs. 缺什麼 vs. 可 Runtime 算 vs. 值得 Persist

| 資料 | 現況 | 建議 |
|---|---|---|
| `operator_path` | 不存在 | 值得 Persist（避免每次請求重算，且需保留 evidence_ref 供審閱） |
| `feature_evidence` | 部分存在（`impact_items.evidence`/`test_cases.evidence` json blob） | 沿用既有欄位，不新建 |
| `graph_node`/`graph_edge` | 不存在獨立表，但邏輯上已被 `GraphifyArtifact#parsed_content` 覆蓋 | **不 Persist**——Runtime 用 `GraphifyGraphIndex` 算 |
| `impact_type`/`risk` | 已存在（`impact_items.impact_level`） | 沿用 |
| `confidence` | Operator Path 需要新欄位；`test_cases.confidence` 亦不存在 | 值得 Persist 於 `operator_paths.confidence_source` + `needs_manual_review` |
| `evidence_id` | 不存在（`evidence_ids` 概念） | 若採用第 9 節的 `evidence_hash` 做法，可不需要逐筆 `evidence_id`，暫緩至 Phase 10 視需要決定 `[V]` |

**不立即加 Migration**——待此計畫核准後，Phase 4/9/10 各自的 migration 才會實際執行，且每個 migration 應獨立、可回滾。`[R]`

---

## 11. File Change Map

依 Phase 分組列出（模式描述，非逐行列舉）：

| Phase | Create | Modify | Delete |
|---|---|---|---|
| 1 | `app/assets/tailwind/application.css`、`bin/dev`、`Procfile.dev`、`app/views/layouts/_header.html.erb` | `Gemfile`、`app/views/layouts/application.html.erb` | — |
| 2 | `app/views/home/_project_row.html.erb`、`app/helpers/application_helper.rb`（補 `status_badge`） | `app/views/home/index.html.erb` | — |
| 3 | `app/views/projects/_business_module_table.html.erb`、`_feature_row.html.erb`、`app/javascript/controllers/disclosure_controller.js` | `app/views/projects/show.html.erb`、`app/controllers/projects_controller.rb` | — |
| 4 | `app/models/operator_path.rb`、`operator_path_segment.rb`、`app/services/operator_path_resolver.rb`、migration files、`app/views/projects/_operator_path.html.erb` | `app/models/concerns/model_enum.rb`、`app/actors/projects/build_business_features.rb`（或新 job 觸發點） | — |
| 5 | — | `tabs/_technical.html.erb`、`projects/pull_request_analyses_controller.rb` | — |
| 6 | — | `tabs/_business.html.erb`、`pull_request_analyses/show.html.erb` | — |
| 7 | `tabs/_diff_file.html.erb`、`app/assets/tailwind` 內 diff 相關 utility 若需要 | `tabs/_raw_diff.html.erb` | — |
| 8 | `config/importmap.rb` pin、`app/javascript/controllers/graph_controller.js`、新 controller/route、`_graph_inspector.html.erb` | `tabs/_graphify.html.erb` | — |
| 9 | `skills/test_scope/{skill.md,input_schema.json,output_schema.json}` | `app/services/llm/test_scope_prompt.rb`、migration（`test_reports` 加 2 欄） | — |
| 10 | `app/services/llm/evidence_hash.rb`、`test/services/llm/cross_provider_consistency_test.rb`、migration（`test_reports` 加 2 欄） | `app/services/llm/{provider,claude_provider,gemini_provider,open_ai_provider}.rb` | — |
| 11 | `test/system/**` 新增檔案 | 各 CSS 微調 | `app/javascript/controllers/hello_controller.js`（未使用的生成器樣板） |

全程**不刪除任何現有 model/schema**，只新增與強化。`[R]`

---

## 12. Implementation Phases

每個 Phase 皆獨立可交付，含 Goal / Files / Backend Changes / Frontend Changes / Tests / Acceptance Criteria。

### Phase 1 — Design System / Layout Shell
- **Goal**：建立 tailwindcss-rails、design token、layout shell，零頁面內容改變。
- **Files**：見第 11 節 Phase 1 列。
- **Backend**：無。
- **Frontend**：`gem "tailwindcss-rails"`、`rails tailwindcss:install`、`@theme` token、header partial、flash 渲染。
- **Tests**：system test 確認每頁 render 無 console/asset 錯誤。
- **Acceptance**：現有頁面內容不變但套用一致樣式；flash 訊息可見（目前完全沒有）。

### Phase 2 — Homepage 重設計
- **Goal**：首頁 table 化 + status badge，定位為 Project Dashboard。
- **Files**：見第 11 節。
- **Backend**：無（`Project#status_text`/`analysis_status_text` 已存在）。
- **Frontend**：`_project_row.html.erb`、badge helper。
- **Tests**：view test 斷言 badge 依 `project.status` 正確渲染。
- **Acceptance**：專案列表為 Table，可 Hover，可 Expand，可快速進入 Project/PR/Graphify。

### Phase 3 — Business/Technical Table View
- **Goal**：`projects#show` 表格化 + pagination + lazy 展開。
- **Files**：見第 11 節。
- **Backend**：`ProjectsController#show` 加分頁 scope，確認 `.includes(business_features: :code_entities)` 涵蓋技術視圖避免 N+1。
- **Frontend**：table CSS、`disclosure_controller.js`。
- **Tests**：controller test（分頁參數）+ system test（row 展開 lazy-load）。
- **Acceptance**：數百 feature 不造成 N+1 查詢暴增（需加查詢數斷言）。

### Phase 4 — Operator Path 架構
- **Goal**：新表 + `OperatorPathResolver` + 顯示於 feature row。
- **Files**：見第 7、10、11 節。
- **Backend**：migration、resolver service、`model_enum.rb` 新增 enum。
- **Frontend**：`_operator_path.html.erb`、「需要人工確認」badge。
- **Tests**：`OperatorPathResolver` 涵蓋 5 個證據層級的 unit test（fixture-based，比照 `test/services/routes_file_parser_test.rb` 風格）。
- **Acceptance**：已知 fixture 專案的每個 feature，要嘛顯示有證據的真實路徑，要嘛明確顯示「需要人工確認」——零憑空文字。

### Phase 5 — Technical View 強化
- **Goal**：`_technical.html.erb` 表格化 + impact_level 篩選。
- **Files**：見第 11 節。
- **Backend**：`impact_items` 篩選 scope、`.includes` 覆查。
- **Frontend**：Table + badge 複用、`<select>` 篩選（不需要 JS，沿用 `?view=` 慣例）。
- **Tests**：controller test（篩選參數）+ view test。
- **Acceptance**：篩選後其他 query param 保留（`?tab=technical&impact_level=direct_change`）。

### Phase 6 — PR Analysis 總覽 + 業務視圖重設計
- **Goal**：`_business.html.erb` 表格化、PR Header 樣式化、串接 Operator Path。
- **Files**：見第 11 節。
- **Backend**：無新增（既有 `.includes` 已覆蓋）。
- **Tests**：view test 確認 risk 分組/排序不變（`ImpactItem::RISK_ORDER`）。
- **Acceptance**：操作人員不需讀 raw JSON 即可知道「改了什麼／要去哪測」。

### Phase 7 — Diff Viewer
- **Goal**：逐行渲染取代 `<pre>`，複用 `GitDiffParser`。
- **Files**：見第 11 節。
- **Backend**：確認 `GitDiffParser` 輸出形狀是否需要 presenter 轉接（`[V]` 需實作時驗證其確切輸出結構）。
- **Tests**：view test（fixture diff）。
- **Acceptance**：Changed File 清楚、新增/刪除清楚、可快速跳檔案；大型 diff 不會讓頁面卡住（超長檔案考慮 Turbo Frame 展開）。

### Phase 8 — Graphify IDE
- **Goal**：三欄 IDE（Explorer/Canvas/Inspector）。
- **Files**：見第 8、11 節。
- **Backend**：新 controller action（node detail），depth-cap 初始 render。
- **Frontend**：`config/importmap.rb` pin Cytoscape、`graph_controller.js`。
- **Tests**：system test（需確認 JS driver 是否已配置 `[V]`）+ controller action 的 depth-cap unit test。
- **Acceptance**：不再只能看 JSON；可 Zoom/Pan/Search/Filter；Hover 可 Highlight Dependency；Click 可查看 Inspector；可由 Feature 追到 Code、由 Code 反查 Feature。

### Phase 9 — Canonical LLM Skill 封裝
- **Goal**：外部化 `skills/test_scope/`，不改變 runtime 行為。
- **Files**：見第 9、11 節。
- **Backend**：`test_reports` 加 `skill_version`/`schema_version`。
- **Tests**：斷言載入的 skill 內容與 `TestScopeSchema` 期望一致。
- **Acceptance**：生成報告行為不變；每筆新 `TestReport` 記錄 `skill_version`。

### Phase 10 — 跨 Provider 一致性基礎建設
- **Goal**：`evidence_hash`、`temperature`、cross-provider fixture test。
- **Files**：見第 9、11 節。
- **Backend**：2 個新欄位、`EvidenceHash` service、3 個 provider 補 `temperature` 傳遞。
- **Tests**：`cross_provider_consistency_test.rb`（stub-based，非真實付費呼叫，因目前從未真正打過付費 API `[C]`）。
- **Acceptance**：同一 evidence 輸入通過三個 provider stub，皆通過 schema 驗證且結構一致。

### Phase 11 — 測試、無障礙與收尾
- **Goal**：system test 全面覆蓋、無障礙、空/錯誤/載入狀態複查。
- **Files**：見第 11 節。
- **Backend**：無。
- **Frontend**：`:focus-visible`、`prefers-reduced-motion`（Graph 動畫）、清理未使用的 `hello_controller.js`。
- **Tests**：全頁 system test sweep。
- **Acceptance**：所有先前 Phase 的 acceptance criteria 一起複查，無回歸。

---

## Acceptance Criteria 總覽

**Homepage**：已匯入專案使用 Table；可 Hover；可 Expand；可快速進入 Project/PR/Graphify。
**Project**：Business Feature 為 Table；操作人員路徑清楚；Technical Detail 可展開；搜尋與 Filter 可用。
**Graphify**：不再只能看 JSON；每個 Project 有自己的 Graphify IDE；可 Zoom/Pan/Search/Filter；Hover 可 Highlight Dependency；Click 可查看 Inspector；可由 Feature 追到 Code、可由 Code 反查 Feature。
**PR Analysis**：Test Scope 為預設 Tab；測試案例表格化；每筆可展開；操作人員步驟為主要資訊；Technical Evidence 預設收起。
**Diff**：Changed File 清楚；新增/刪除清楚；可快速跳檔案。
**LLM**：無論 Claude/Gemini/OpenAI，都讀取同一 Evidence Pack、使用同一 Skill、符合相同 JSON Schema、使用相同 Business Feature、使用相同 Operator Path Evidence、輸出相同 Report Structure。

---

## 從 Code 可確定 / 設計建議 / 需實作時驗證 三類總結

**`[C]` 從目前 Code 可以確定**：
- 現有前端技術棧（Rails 7.1.6/Sprockets/importmap-rails/turbo-rails/stimulus-rails，全部未實際使用）
- 全站零 CSS、零 Table、零圖形視覺化、僅 6 個 partial
- Backend 網域模型完整存在（Project/BusinessModule/BusinessFeature/CodeEntity/PullRequestAnalysis/ChangedFile/ImpactItem/GraphifyArtifact/TestReport/TestCase）
- `GraphifyGraphIndex`、`RoutesFileParser`、`BusinessFeatureNamer` 等既有服務的實際行為
- LLM Provider/Prompt/Schema/Report Renderer 管線已是 provider-agnostic 且真實運作
- Operator Path 相關欄位/概念完全不存在於 schema 或程式碼中
- 姊妹專案 DependencyWeb 的實際樣式機制（tailwindcss-rails）與技術債（零元件抽象、零 Stimulus、死碼相依套件）

**`[R]` 設計建議**：
- Cytoscape.js 選型、Operator Path 兩張新表的具體欄位設計、Design Token 結構、Component Plan 的 Partial/Stimulus 切分、11 個 Implementation Phase 的順序與內容、LLM 一致性的補強項目清單

**`[V]` 需實作時驗證**：
- `GitDiffParser` 的確切輸出結構是否需要額外 presenter 轉接（Phase 7）
- 是否已配置 Capybara JS driver 供 Graphify IDE 的 system test 使用（Phase 8）
- Operator Path 解析時機（build-time vs. lazy resolve，Phase 4）
- 分頁是否引入 Kaminari 或手刻 scope（Phase 3）
- `evidence_id` 逐筆追蹤是否在 Phase 10 之外仍需要（目前傾向用 `evidence_hash` 取代）

---

## 完成後續

依 `docs/frontend_plan.md` 第八十一節指示，本文件完成後**停止**，不進行任何程式碼修改，等待下一步實作指令。
