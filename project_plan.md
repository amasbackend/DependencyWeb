# 任務：重新建立一個 Ruby on Rails「GitHub 程式碼相依性／PR 測試範圍分析網站」

你現在要從零重新建立一個 Ruby on Rails 網站。

這不是單純的 Git Diff Viewer，也不是單純的程式碼 Dependency Graph。

這個系統最終目的為：

> **匯入一個既有 Ruby on Rails GitHub 專案，建立母分支的功能／Model／Actor／Controller 等結構索引；之後輸入 PR Number，自動分析 PR 相對於母分支的程式碼差異、Graphify 相依性，再交由 LLM 推導成「現場操作人員看得懂的測試範圍」。**

---

# 0. 開發前必須先閱讀的既有專案

不要直接開始寫程式。

先完整閱讀以下兩個專案。

## A. 主要架構參考

```text
/home/micky/PrjAGWms
```

重點研究：

* Rails MVC 結構
* Controller 寫法
* Model 寫法
* Actor / Service Actor 的使用方式
* Blueprint 的使用方式
* routes 組織方式
* concern
* validation
* transaction
* error handling
* API response
* namespace
* query object / service object（如果有）
* background job（如果有）
* 前端 View / JS / CSS 結構
* i18n
* application configuration
* test / spec 結構

新的網站應盡量遵循此專案的：

* 命名方式
* MVC 邊界
* Actor Pattern
* Blueprint Pattern
* Error Handling Pattern
* Transaction Pattern
* Coding Style

不要擅自另外建立一套完全不同的 Rails 架構。

---

## B. GitHub Dependency 功能參考

```text
/home/micky/DependencyWeb
```

這個專案可能已經存在部分：

* GitHub 專案匯入
* GitHub API
* Branch
* PR
* Git Diff
* 程式碼掃描
* Graphify
* LLM
* Dependency Analysis
* Management Page
* Feature Analysis

相關功能。

請：

1. 找出哪些功能可以重用。
2. 找出哪些邏輯可以移植。
3. 找出哪些程式碼有架構問題。
4. 不要直接整份 Copy。
5. 將有價值的邏輯重新整理成符合 `/home/micky/PrjAGWms` 架構的新實作。

---

# 1. 開發原則

這是一個「重新建立」的網站。

不要因為 DependencyWeb 已有功能，就在原本程式碼上不斷堆 patch。

新的系統必須：

```text
Controller
   ↓
Actor / Service
   ↓
Domain / Model
   ↓
Repository / GitHub / Graphify / LLM
```

Controller 不可包含大量：

* Git 操作
* GitHub API 邏輯
* Graphify 執行邏輯
* LLM Prompt
* Diff Parser
* Shell Command
* 商業邏輯

這些全部拆入 Actor / Service。

---

# 2. 第一階段：先分析再實作

開始修改程式以前，先產生：

```text
docs/architecture_plan.md
```

內容至少包含：

1. PrjAGWms 可參考的架構模式
2. DependencyWeb 可重用的功能
3. 新網站 Domain Model
4. Database Schema
5. Actor 列表
6. Controller 列表
7. Blueprint 列表
8. Git Repository 儲存方式
9. Graphify Pipeline
10. PR Analysis Pipeline
11. LLM Analysis Pipeline
12. Test Report Pipeline
13. 頁面與 Route 規劃
14. Background Job 規劃
15. Error Handling
16. Security

完成 architecture_plan 後，再進行程式實作。

---

# 3. GitHub Token

使用：

```text
GITHUB_ACCESS_TOKEN
```

Environment Variable。

例如：

```text
ENV.fetch("GITHUB_ACCESS_TOKEN")
```

禁止：

* hard code token
* token 存入 Git
* token 出現在 log
* token 出現在 exception
* token 顯示在畫面
* 將完整 authenticated clone URL 存進 DB

---

# 4. GitHub Project 匯入

首頁需要提供：

```text
GitHub 專案匯入
```

使用者輸入：

```text
Owner
Repository
```

例如：

```text
Owner:
AMASTek

Repository:
PrjJieZhou
```

Branch 預設不需要使用者輸入。

系統必須透過 GitHub API 取得：

```text
repository.default_branch
```

例如：

```text
main
master
develop
```

以 GitHub 實際 Default Branch 為準。

---

# 5. Repository 本地儲存

取得 Default Branch 後：

1. 抓取 GitHub repository
2. checkout Default Branch
3. 保存母分支 SHA
4. 將 repository 保存在本網站管理的 repository storage 中

建議：

```text
storage/repositories/
  AMASTek/
    PrjJieZhou/
      repository.git
      worktrees/
```

實際實作可以依現有專案環境調整。

Repository Path 必須可透過設定：

```text
REPOSITORY_ROOT
```

不要把絕對路徑散落在程式裡。

---

# 6. Git Repository 管理原則

請避免直接：

```text
git checkout branchA
git checkout branchB
```

共用同一個 working directory。

因為之後可能同時分析：

```text
PR #123
PR #124
PR #125
```

優先考慮：

```text
bare repository
+
git worktree
```

或其他可以隔離分析環境的方式。

每個 Analysis 必須擁有獨立 workspace。

例如：

```text
storage/repositories/AMASTek/PrjJieZhou/worktrees/pr-123/
```

Analysis 完成後可以清理 temporary worktree。

---

# 7. 安裝 Graphify

所有匯入的 Repository 都是 Ruby on Rails 專案。

每個 Repository 匯入完成後，需要準備 Graphify 分析環境。

重要：

不要直接假設 Graphify 的 CLI、Gem Name 或設定方式。

先檢查：

1. `/home/micky/DependencyWeb`
2. 現有 Graphify integration
3. 實際可使用的 Graphify command/API
4. Gem / CLI 的安裝方式

再依實際環境實作。

---

# 8. Graphify 不可污染原始 Repository

如果 Graphify 需要：

```ruby
gem "..."
```

或其他設定才可以執行：

禁止直接修改保存的母分支內容。

可以：

```text
Analysis Worktree
```

內加入必要設定。

Graphify 執行產生的任何：

```text
Gemfile
Gemfile.lock
config
output
graph
json
tmp
```

都只能存在 Analysis Workspace。

不可：

* commit
* push
* 改變真正的 GitHub repository
* 污染 baseline

---

# 9. Project Model

至少需要類似：

```text
Project
```

欄位可包含：

```text
id
owner
repository_name
github_full_name

default_branch

repository_path

base_sha
last_synced_sha
last_synced_at

status
analysis_status

created_at
updated_at
```

狀態不要只使用散落字串。

可考慮：

```text
pending
cloning
installing
analyzing
ready
failed
```

---

# 10. Base Branch Code Index

Project 匯入成功後，需要掃描母分支。

系統不能只知道：

```text
app/models/user.rb
app/controllers/users_controller.rb
```

而是需要建立：

```text
Model
Controller
Actor
Route
View
Feature
Business Module
```

之間的結構。

---

# 11. Business Module

最重要的 Domain 概念之一：

```text
BusinessModule
```

注意：

Business Module 不是 Ruby Module。

Business Module 是「操作人員理解的功能模組」。

例如：

```text
使用者
客戶
訂單
庫存
工單
報廢
調撥
包裝
權限
登入
```

---

# 12. Business Feature

另一個核心 Domain：

```text
BusinessFeature
```

例如：

```text
使用者列表
使用者查詢
新增使用者
編輯使用者
刪除使用者

客戶列表
新增客戶
編輯客戶

工單列表
工單建立
工單修改
工單結案

A3 冷卻
A5 異常品項維護
WMS 報廢
```

不要把：

```text
UsersController#index
UsersController#update
Api::Users::UpdateActor
```

直接當作 UI 上的「功能名稱」。

這些是 Technical Entity。

Business Feature 必須是：

> 人類實際在系統裡可以做的事情。

---

# 13. Feature 建立來源

Feature 可以綜合：

```text
routes.rb
Controller
Controller Action
Actor
Model
View
Partial
Form
JS
i18n locale
menu
navigation
authorization
Graphify dependency
```

推導。

例如發現：

```text
GET /users
UsersController#index
users/index.html.erb
```

可以推導：

```text
模組：使用者
功能：使用者列表
```

如果：

```text
GET /users/:id/edit
PATCH /users/:id
```

則：

```text
模組：使用者
功能：編輯使用者
```

---

# 14. CRUD 中文 Feature Mapping

可建立初步 Rule：

```text
index
→ 列表 / 查詢

show
→ 詳細資料 / 查看

new + create
→ 新增

edit + update
→ 編輯

destroy
→ 刪除
```

但這只能當初步規則。

因為實際專案中可能有：

```text
cooling
packing
receive
finish
scrap
approve
release
sync
```

等 Domain Action。

這時應綜合：

```text
route
controller
actor
view
locale
```

判斷真正的 Business Feature。

---

# 15. 優先使用既有中文資訊

若 Repository 本身存在：

```text
config/locales/*.yml
```

或：

```text
navigation
menu
breadcrumb
page title
button text
```

優先使用既有中文名稱。

例如程式有：

```yaml
users:
  title: 使用者管理
```

不要讓 LLM 重新翻成：

```text
帳戶人員模組
```

造成系統術語不一致。

---

# 16. Technical Entity

另外建立 Technical Entity / Code Entity。

例如：

```text
CodeEntity
```

類型：

```text
model
controller
actor
service
blueprint
job
mailer
route
view
javascript
concern
validator
serializer
```

保存：

```text
name
type
file_path
class_name
method_name
line_start
line_end
```

---

# 17. Feature ↔ Code Entity 關聯

需要能建立：

```text
BusinessFeature
      ↓
FeatureCodeEntity
      ↓
CodeEntity
```

例如：

```text
編輯使用者
  ↓
UsersController#edit
UsersController#update
Users::UpdateActor
User
users/edit.html.erb
```

目的：

當 PR 修改：

```text
Users::UpdateActor
```

系統可以反向推導：

```text
可能影響：
使用者 → 編輯使用者
```

---

# 18. 首頁

首頁參考目前 DependencyWeb 的風格，但重新整理。

首頁至少包含：

```text
GitHub 專案匯入
已匯入專案
```

---

# 19. 已匯入專案列表

顯示每一個 Project Card。

例如：

```text
PrjJieZhou

Owner:
AMASTek

Default Branch:
test/i18n

Last Sync:
2026-08-18 20:40

Status:
Ready
```

操作：

```text
查看專案
同步母分支
刪除
```

刪除必須有 Confirmation。

---

# 20. Project Detail Page

點入 Project 後，畫面需要至少包含：

```text
專案資訊

母分支同步

Business Module

Business Feature

GitHub PR 分析

歷史 PR 分析
```

---

# 21. 模組檢視

例如：

```text
使用者
  ├─ 使用者列表
  ├─ 新增使用者
  ├─ 編輯使用者
  └─ 刪除使用者

客戶
  ├─ 客戶列表
  ├─ 新增客戶
  └─ 編輯客戶

庫存
  ├─ 庫存查詢
  ├─ 庫存調整
  ├─ 調撥
  └─ 報廢
```

這才是主要畫面。

不是：

```text
UsersController
CustomerActor
WmsStock
```

---

# 22. Technical View

Business View 旁邊可以提供：

```text
技術視圖
```

例如：

```text
編輯使用者

Route
PATCH /users/:id

Controller
UsersController#update

Actor
Users::UpdateActor

Models
User
Role
Permission

Views
users/edit.html.erb
```

Business View 為預設。

Technical View 為輔助。

---

# 23. 母分支同步

Project Page 提供：

```text
同步 GitHub 母資料
```

按鈕。

點擊後：

1. GitHub API 重新取得 default branch
2. fetch repository
3. 更新 default branch
4. 更新 Base SHA
5. 重新建立 Code Index
6. 更新 Graphify Index
7. 更新 Business Module
8. 更新 Business Feature

同步成功後更新：

```text
last_synced_at
last_synced_sha
```

---

# 24. PR Analysis

Project Page 提供：

```text
PR Number:
[           ]

[查詢 PR]
[分析 PR]
```

使用者輸入：

```text
65
```

系統透過 GitHub API 取得：

```text
PR number
title
description
author
base branch
base sha
head branch
head sha
changed files
```

---

# 25. PR 匯入流程

按：

```text
分析 PR
```

之後自動完成整條 Pipeline。

```text
PR Number
   ↓
GitHub PR Metadata
   ↓
Fetch PR Head
   ↓
建立 Analysis Worktree
   ↓
Git Diff
   ↓
Diff Parser
   ↓
Graphify
   ↓
Dependency Impact
   ↓
Business Feature Mapping
   ↓
LLM Analysis
   ↓
Test Report
```

使用者不應再手動按：

```text
下載 Branch
產生 Diff
執行 Graphify
呼叫 Gemini
產生 Report
```

全部是一個 Analysis Job。

---

# 26. Git Diff

比較：

```text
母分支
vs
PR Head
```

應使用正確 merge base。

概念上：

```bash
git merge-base BASE HEAD
```

再分析真正由 PR 帶來的修改。

不要單純相信：

```text
目前 checkout branch
```

---

# 27. Diff 保存內容

建立：

```text
PullRequestAnalysis
```

至少保存：

```text
project_id
pr_number

pr_title
pr_description
pr_author

base_branch
base_sha

head_branch
head_sha

merge_base_sha

status

started_at
finished_at

error_message
```

另外保存：

```text
ChangedFile
```

例如：

```text
file_path
change_type
additions
deletions
patch
```

---

# 28. Diff Parser

不要只把一大包 raw diff 直接丟給 LLM。

先解析：

```text
Changed File
Changed Class
Changed Method
Changed Actor
Changed Model
Changed Controller
Changed Route
Changed View
Changed Validation
Changed Association
```

讓後續 Graphify / LLM 使用結構化資料。

---

# 29. Graphify Analysis

對 PR Analysis Workspace 執行 Graphify。

需要取得：

```text
Direct Dependency
Indirect Dependency
Call Graph
Model Relation
Controller Relation
Actor Relation
```

如果 Graphify 能提供其他 Rails dependency 資訊，也應保留。

保存原始 Graphify Result。

例如：

```text
GraphifyArtifact
```

欄位：

```text
pull_request_analysis_id
format
raw_content
parsed_content
created_at
```

---

# 30. Impact Analysis

Graphify 結果與 Diff 必須交叉分析。

例如：

```text
PR 修改：

Wms::Stock::UpdateActor
```

Graphify 發現：

```text
A3 Cooling
      ↓
UpdateUsageActor
      ↓
Wms::Stock::UpdateActor

A5 Pack
      ↓
UpdateUsageActor
      ↓
Wms::Stock::UpdateActor
```

則不能只輸出：

```text
修改 Wms::Stock::UpdateActor
```

應產生：

```text
可能影響：

A3 冷卻
A5 異常品項維護
庫存異常入庫
```

---

# 31. Direct / Indirect Impact

區分：

```text
直接修改
直接依賴
間接依賴
可能回歸
```

例如：

```text
直接修改：
A5 異常品項維護

直接影響：
A3 冷卻

間接影響：
WMS 報廢

回歸確認：
A1 / A2 收貨
```

---

# 32. LLM Provider

設計 Provider abstraction。

例如：

```text
Llm::Provider
```

Implementation：

```text
Llm::GeminiProvider
```

未來可以：

```text
Llm::OpenAiProvider
Llm::ClaudeProvider
```

不要讓 Actor 直接綁死：

```text
Gemini API
```

---

# 33. LLM Environment

例如：

```text
LLM_PROVIDER=gemini
GEMINI_API_KEY=...
GEMINI_MODEL=...
```

API Key 禁止：

* hard code
* DB 明文保存
* log
* HTML
* exception message

---

# 34. LLM Input

不要把整個 Repository 全部塞入 Prompt。

輸入應整理為：

```text
Project Information

PR Metadata

PR Description

Changed Files

Changed Classes

Changed Methods

Relevant Git Diff

Graphify Direct Dependencies

Graphify Indirect Dependencies

Mapped Business Modules

Mapped Business Features

Routes

Relevant Models

Relevant Actors

Relevant UI / Views

Relevant i18n Text
```

只餵與 PR 相關的 Context。

---

# 35. LLM 的主要任務

LLM 不是做：

```text
Code Review
```

主要是：

> 將技術修改翻譯成「操作人員要測哪些頁面、做什麼操作、看到什麼結果」。

例如：

不要：

```text
UpdateUsageActor 改變了 total_be_used_num 計算。
```

而應轉化：

```text
A3 冷卻

操作：
將留切／報廢數量由 5 調整為 3，再儲存。

確認：
沒有真實占用時應能正常儲存；
如果已有報廢或調撥占用，則應阻止修改並顯示錯誤訊息。
```

---

# 36. LLM 不得幻想

所有 Test Case 必須能追蹤 Source Evidence。

例如：

```json
{
  "feature": "A3 冷卻",
  "reason": "...",
  "evidence": [
    "app/actors/...",
    "app/controllers/...",
    "Graphify: ...",
    "git diff: ..."
  ]
}
```

如果證據不足：

```text
需要人工確認
```

不要自己編造不存在的：

* 頁面
* Button
* 欄位
* Workflow
* Model
* Business Rule

---

# 37. LLM Structured Output

LLM 第一階段必須回傳 Structured JSON。

不要直接要求 LLM 輸出 HTML。

例如：

```json
{
  "summary": {},
  "affected_modules": [],
  "affected_features": [],
  "test_cases": [],
  "regression_cases": [],
  "pass_criteria": [],
  "manual_checks": [],
  "uncertain_items": []
}
```

Rails 驗證 JSON Schema 成功後，再 Render：

```text
HTML
Markdown
```

---

# 38. 測試報告的核心視角

報告主要使用：

```text
現場操作人員／測試人員
```

的視角。

重點是：

```text
去哪個頁面
做什麼
輸入什麼
按什麼
應該看到什麼
什麼情況算失敗
```

而不是：

```text
Method A calls Method B
```

技術資訊可以做為：

```text
分析依據
```

但不要成為報告主體。

---

# 39. Test Report 格式

請依照提供的：

```text
測試報告範例.md
```

的精神設計。

Report 至少包含：

---

## 修改摘要

例如：

| 類型   | 說明         |
| ---- | ---------- |
| 收貨下限 | 修改已使用量判斷   |
| 跨單累加 | 相同原料批改為累加  |
| 錯誤訊息 | 增加品號、批號、倉別 |

---

## 操作頁面 ↔ 驗證目的

例如：

| 場景     | 代表頁面               | 操作人員動作   | 驗證目的   |
| ------ | ------------------ | -------- | ------ |
| A3 冷卻  | `/workstation/...` | 修改冷卻／異常量 | 確認異常庫存 |
| A5 異常  | `/workstation/...` | 修改異常量    | 確認同步   |
| WMS 報廢 | `/wms...`          | 掃碼報廢     | 確認流程鎖  |

---

## 測試前準備

例如：

```text
需要什麼帳號
需要什麼資料
需要哪種工單
需要什麼前置狀態
```

---

## 各模組測試步驟

每個 Case 至少：

```text
名稱

頁面

功能

影響類型

驗證內容

操作步驟

預期結果

失敗判讀

注意事項
```

例如：

```text
### A3 冷卻 — 下調未入包裝

頁面：
/workstation/a3_order/:work_date

驗證內容：
沒有占用時是否能降低異常數量。

操作：

1. 開啟工單。
2. 進入冷卻。
3. 將留切量由 5 改成 3。
4. 儲存。
5. 重新進入畫面。

預期：

儲存成功，數量維持 3。

失敗：

錯誤阻擋，或重新整理後數量不一致。
```

---

## 測試通過標準

集中列出：

```text
哪些條件全部成立才代表 PR 可以通過。
```

---

## 建議測試順序

不是單純按 Controller 排列。

LLM 應依：

```text
核心修改
↓
直接影響
↓
間接影響
↓
Regression
```

安排。

---

## 操作人員回報資訊

例如：

```text
工單
日期
操作頁面
操作內容
修改前
修改後
畫面結果
錯誤訊息
預期結果
Screenshot
```

---

# 40. Report 中同時顯示影響來源

每個 Test Case 可以增加：

```text
為什麼需要測？
```

例如 UI 可以 Collapsible 顯示：

```text
分析依據

PR:
app/actors/a5/update_usage_actor.rb

Graphify:
UpdateUsageActor
→ UpdateWmsStockActor

對應功能:
A5 異常品項維護
```

預設收起。

操作人員不用看。

工程師需要時才打開。

---

# 41. PR 分析結果畫面

Analysis Detail Page 建議：

```text
PR #65
━━━━━━━━━━━━━━━━

Title:
修正 A5 未入包裝累加

Base:
test/i18n

Head:
fix/a5-stock

Changed Files:
18

Affected Models:
13

Affected Features:
8

━━━━━━━━━━━━━━━━

[測試範圍]
[修改內容]
[業務視圖]
[技術視圖]
[Graphify]
[Raw Diff]
```

---

# 42. 測試範圍為預設 Tab

一般使用者進 PR Analysis 後：

預設看到：

```text
測試範圍
```

不是 Git Diff。

---

# 43. Business View

例如：

```text
高風險

A3 冷卻
A5 異常品項維護

中風險

WMS 報廢
A1 收貨
A2 收貨

低風險

庫存查詢
```

風險理由必須由實際 Dependency / Diff 支撐。

---

# 44. Technical View

工程師可以看到：

```text
Changed Actors
Changed Models
Changed Controllers

Direct Dependencies
Indirect Dependencies

Routes

Changed Methods

Graphify Result
```

---

# 45. Raw Diff

提供完整：

```text
git diff
```

但不要將 Raw Diff 當作預設畫面。

---

# 46. Analysis Status

Analysis 是長流程。

需要 Status：

```text
queued
fetching_pr
creating_workspace
diffing
graphifying
mapping_features
llm_analyzing
building_report
completed
failed
```

畫面應能顯示目前進度。

不要讓 HTTP Request 卡住數分鐘。

---

# 47. Background Job

如果 PrjAGWms 已有：

```text
Sidekiq
ActiveJob
```

等 Pattern，直接沿用。

長時間工作：

```text
Git Clone
Git Fetch
Graphify
LLM
Repository Scan
```

必須 Background Processing。

---

# 48. 建議 Actor

依 PrjAGWms 的實際 Actor 寫法調整名稱。

可以考慮：

```text
Projects::ImportActor

Projects::SyncActor

Repositories::CloneActor
Repositories::FetchActor
Repositories::CreateWorktreeActor
Repositories::RemoveWorktreeActor

Projects::IndexCodeActor
Projects::BuildBusinessModulesActor
Projects::BuildBusinessFeaturesActor

PullRequests::FetchActor
PullRequests::PrepareAnalysisActor

Git::DiffActor
Git::ParseDiffActor

Graphify::InstallActor
Graphify::AnalyzeActor
Graphify::ParseResultActor

Impacts::MapCodeEntitiesActor
Impacts::MapBusinessFeaturesActor

Llm::AnalyzeTestScopeActor

Reports::BuildActor
Reports::RenderMarkdownActor
```

但是不要為了套 Pattern 而建立大量只有一兩行的 Actor。

應依 PrjAGWms 的實際 Pattern 做合理拆分。

---

# 49. Actor Orchestration

例如：

```text
PullRequests::AnalyzeActor
```

負責 orchestration：

```text
Fetch PR
→ Fetch Git refs
→ Worktree
→ Diff
→ Parse
→ Graphify
→ Impact Mapping
→ LLM
→ Report
```

每個 Actor 各自負責一個清楚 Responsibility。

---

# 50. Transaction

DB 寫入相關操作必須 Transaction。

尤其：

```text
Project Import
Code Index Rebuild
Feature Mapping
Analysis Result
Report
```

避免：

```text
Analysis completed
但是 Report 不存在
```

這種半完成狀態。

外部：

```text
GitHub
Git
Graphify
LLM
```

不能當成 DB Transaction。

應設計明確 Stage / Retry。

---

# 51. Idempotency

以下操作必須盡可能可重跑：

```text
同步母分支
重新掃描
Graphify
重新分析 PR
重新呼叫 LLM
重新建立 Report
```

例如 PR #65 分析失敗後：

```text
重新分析
```

不可建立大量重複髒資料。

---

# 52. Analysis Snapshot

歷史 Analysis 必須記住當時：

```text
base_sha
head_sha
```

不能因為母分支後來更新，就讓舊報告內容偷偷改變。

每一份 Test Report 都對應固定：

```text
BASE SHA
HEAD SHA
```

---

# 53. Project Base Branch 與 PR Base

如果 PR 的：

```text
base branch
```

不是目前 Project 的：

```text
default branch
```

不要偷偷當成一樣。

畫面顯示 Warning：

```text
此 PR Base Branch 與專案目前母分支不同。
```

並使用實際 PR Base SHA 分析。

---

# 54. UI 設計方向

可參考目前 DependencyWeb Screenshot：

首頁：

```text
關聯文件
GitHub 專案匯入
Project Card
```

匯入頁：

```text
Owner
Repository
Branch
開始匯入
```

新的版本 Branch 預設應改為：

```text
自動讀取 GitHub Default Branch
```

只有 Advanced Option 才允許人工 Override。

---

# 55. Project Management Page

目前畫面已有類似：

```text
搜尋

全部
異動檔案
業務視圖
技術視圖

GitHub 母資料同步
GitHub PR 分析

功能路徑
Actor
Model
查詢欄位
修改欄位
刪除欄位
Status
```

新的版本可以保留有價值的資訊。

但是畫面核心應從：

```text
「程式碼檔案」
```

提升成：

```text
「Business Module / Business Feature」
```

技術資訊放第二層。

---

# 56. 搜尋

Project Page 搜尋至少支援：

```text
中文功能名稱
Route
Controller
Actor
Model
File Path
```

例如搜尋：

```text
使用者
```

可以得到：

```text
使用者列表
使用者編輯
使用者新增
```

並看到其 Technical Dependency。

---

# 57. Blueprint

若 PrjAGWms 使用 Blueprinter：

API Response 也使用相同 Pattern。

例如：

```text
ProjectBlueprint
BusinessModuleBlueprint
BusinessFeatureBlueprint
CodeEntityBlueprint
PullRequestAnalysisBlueprint
TestReportBlueprint
```

不要 Controller 手寫巨大 JSON。

---

# 58. Controller

例如：

```text
ProjectsController

ProjectSyncsController

PullRequestAnalysesController

BusinessModulesController
BusinessFeaturesController

TestReportsController
```

實際命名請依 PrjAGWms route/controller 慣例調整。

---

# 59. Database 建議

Domain 至少考慮：

```text
projects

business_modules
business_features

code_entities
feature_code_entities

pull_request_analyses
changed_files
changed_code_entities

graphify_artifacts

impact_items

test_reports
test_cases
```

不要為每一個 Graphify Node 都過度正規化。

Raw Artifact 可使用：

```text
JSON / JSONB
TEXT
```

保存。

真正需要搜尋／關聯的資料才進 relational table。

---

# 60. TestReport

例如：

```text
TestReport

pull_request_analysis_id

title
summary

markdown_content

structured_content

generated_by
model_name
prompt_version

created_at
```

---

# 61. Prompt Version

LLM Prompt 必須有版本。

例如：

```text
TEST_SCOPE_PROMPT_VERSION=v1
```

保存到 TestReport。

未來 Prompt 調整後才知道：

```text
這份 Report 是哪個 Prompt 產生。
```

---

# 62. LLM Cost Control

避免：

```text
整份 Repository
→ LLM
```

使用：

```text
Diff
→ Graphify
→ Relevant Code Extraction
→ Business Feature
→ LLM
```

並記錄：

```text
input token
output token
provider
model
duration
```

如果 Provider 有提供 usage。

---

# 63. LLM Failure

LLM Error 不得讓：

```text
Git Diff
Graphify
Impact Mapping
```

全部消失。

例如狀態：

```text
llm_failed
```

使用者可以：

```text
重新產生測試報告
```

而不必重新下載 Git / 重跑所有分析。

---

# 64. Security

所有 shell command：

禁止：

```ruby
system("git clone #{user_input}")
```

直接拼接。

避免 Command Injection。

Owner：

```text
^[A-Za-z0-9_.-]+$
```

Repository：

使用安全 validation。

PR Number：

Integer only。

Repository Path：

必須防止：

```text
../
```

Path Traversal。

---

# 65. GitHub URL

不要讓使用者直接輸入任意：

```text
ssh command
shell command
URL option
```

主要輸入：

```text
owner
repository
```

由系統自行組成 GitHub API request。

---

# 66. Logging

每個 Analysis 建立：

```text
analysis_id
```

Log 可以：

```text
[PRAnalysis:123]
```

追蹤。

例如：

```text
[PRAnalysis:123] Fetching PR metadata
[PRAnalysis:123] Diff generated
[PRAnalysis:123] Graphify completed
[PRAnalysis:123] LLM analysis completed
```

不要 log：

```text
token
API key
完整敏感 source
```

---

# 67. 錯誤處理

UI 不可只顯示：

```text
Internal Server Error
```

例如：

```text
GitHub Repository 找不到

GitHub Token 權限不足

PR #65 不存在

Graphify 安裝失敗

Graphify 執行失敗

LLM API 回應失敗

LLM 回傳格式錯誤
```

需要可理解訊息。

技術 Detail 保存 log。

---

# 68. Automated Test

至少為核心流程建立測試。

包括：

```text
Project Import

GitHub Default Branch

Project Sync

PR Fetch

Diff Parser

Feature Mapping

LLM JSON Parser

Test Report Builder
```

外部 API 使用 Stub / Fake。

不要讓 test suite 真的：

```text
call GitHub
call Gemini
```

---

# 69. Feature Mapping Test

特別建立：

```text
technical entity
→
business feature
```

測試。

例如：

```text
UsersController#index
→
使用者列表
```

以及 Domain Action：

```text
CoolingActor
→
A3 冷卻
```

---

# 70. Report Parser Test

測試：

```text
LLM 回傳正常 JSON

LLM 回傳缺欄位

LLM 回傳非法 JSON

LLM timeout

LLM 回傳未知 Feature
```

都不能讓整個 Rails App 500。

---

# 71. 第一版 MVP 完成條件

不要一開始做過度龐大的平台。

第一階段完成以下完整 Vertical Slice：

### A

```text
GitHub Project Import
```

↓

### B

```text
取得 Default Branch
```

↓

### C

```text
下載 Repository
```

↓

### D

```text
Graphify Ready
```

↓

### E

```text
Base Branch Code Scan
```

↓

### F

```text
Business Module / Feature
```

↓

### G

```text
Project Detail Page
```

↓

### H

```text
Input PR Number
```

↓

### I

```text
Git Diff
```

↓

### J

```text
Graphify
```

↓

### K

```text
Impact Mapping
```

↓

### L

```text
LLM
```

↓

### M

```text
Operator Test Report
```

↓

### N

```text
UI Display
```

這一整條能跑完才算 MVP。

---

# 72. 不要做的事情

禁止：

### 1.

把這個網站做成只有：

```text
Model Dependency Viewer
```

### 2.

只列：

```text
Actor
Model
Controller
```

卻沒有：

```text
使用者列表
使用者編輯
客戶列表
A3 冷卻
A5 異常
```

這種操作功能。

### 3.

PR Analysis 只顯示：

```text
Changed Files
```

### 4.

LLM Report 全部使用工程術語。

### 5.

把整個 Repository 丟給 LLM。

### 6.

把 Graphify output 直接當 Report。

### 7.

在 Controller 裡塞 Git / LLM / Graphify。

### 8.

直接複製 DependencyWeb 的舊架構。

### 9.

為了「看起來架構漂亮」建立大量沒有價值的 abstraction。

---

# 73. 最重要的資料流

整個系統的核心應該是：

```text
                     GitHub
                       │
                       ▼
                Rails Repository
                       │
                       ▼
                 Base Code Index
                       │
             ┌─────────┴──────────┐
             ▼                    ▼
       Technical Entity      Business Feature
             │                    │
             └──────────┬─────────┘
                        │
                        ▼
                  Feature Mapping


PR Number
    │
    ▼
GitHub PR
    │
    ▼
Git Diff
    │
    ▼
Changed Code Entity
    │
    ▼
Graphify
    │
    ▼
Dependency Impact
    │
    ▼
Business Feature Impact
    │
    ▼
LLM
    │
    ▼
Operator Test Scope
    │
    ▼
Test Report
```

---

# 74. 核心設計思想

這個網站有三層。

## Layer 1 — Code

```text
Model
Controller
Actor
Route
View
Method
File
```

回答：

> 改了什麼程式？

---

## Layer 2 — Business Feature

```text
使用者列表
使用者編輯
客戶管理
庫存調撥
A3 冷卻
A5 異常
```

回答：

> 改到什麼功能？

---

## Layer 3 — Operator Test

```text
去哪個頁面
做什麼操作
輸入什麼資料
看到什麼結果
哪些功能需要回歸
```

回答：

> 操作人員到底要測什麼？

---

這三層不可混為一談。

本系統真正的價值是：

```text
Code Change
       ↓
Dependency
       ↓
Business Impact
       ↓
Human Test Scope
```

---

# 75. 開發順序

請依照：

```text
Phase 1
Architecture / DB

Phase 2
GitHub Project Import

Phase 3
Repository Manager

Phase 4
Graphify Integration

Phase 5
Base Code Index

Phase 6
Business Module / Feature

Phase 7
Project UI

Phase 8
PR Import

Phase 9
Git Diff

Phase 10
Graphify PR Impact

Phase 11
Feature Impact

Phase 12
LLM

Phase 13
Test Report

Phase 14
UI Polish

Phase 15
Automated Tests
```

實作。

---

# 76. 每完成一個 Phase 必須驗證

不要一路寫到底才測試。

每個 Phase：

```text
Implement
→ Test
→ Fix
→ Commit-ready state
→ Next Phase
```

如果發現既有設計不適合：

先修正：

```text
docs/architecture_plan.md
```

再修改程式。

---

# 77. 最終交付說明

完成後新增：

```text
docs/system_architecture.md
```

內容說明：

```text
整體 Architecture
Database
GitHub Pipeline
Repository Storage
Graphify Pipeline
Business Feature Mapping
PR Analysis Pipeline
LLM Pipeline
Test Report Pipeline
Background Job
ENV
Deployment 注意事項
```

以及：

```text
docs/setup.md
```

說明：

```text
bundle install
database setup
GitHub Token
Graphify
LLM Provider
Background Worker
Server
```

---

# 78. 最後驗收情境

至少實際驗證以下完整情境：

```text
1. 開啟首頁

2. GitHub 專案匯入

Owner:
AMASTek

Repository:
PrjJieZhou

3. 系統自動取得 Default Branch

4. Repository 匯入完成

5. Graphify Ready

6. Base Scan 完成

7. 回首頁看到 PrjJieZhou

8. 點入 Project

9. 可以看到：

   使用者
     ├ 使用者列表
     ├ 使用者編輯

   客戶
     ├ 客戶列表
     ├ 客戶編輯

   或該專案實際存在的 Business Feature

10. 輸入 PR Number

11. 按「分析 PR」

12. 系統自動：

GitHub
→ Diff
→ Graphify
→ Dependency
→ Business Feature
→ LLM
→ Report

13. 畫面顯示：

修改摘要

影響模組

影響功能

操作頁面

測試步驟

預期結果

Regression

通過標準

14. 可以切換：

業務視圖
技術視圖
Graphify
Git Diff

15. 可以下載／查看 Markdown Test Report。
```

只有完整走通以上流程，才算此專案的第一版完成。

---

# 79. 開始工作前

現在不要立即大量產生程式碼。

第一步：

```text
cd /home/micky/PrjAGWms
```

分析其架構。

第二步：

```text
cd /home/micky/DependencyWeb
```

分析可重用功能。

第三步：

整理兩邊差異。

第四步：

在新專案建立：

```text
docs/architecture_plan.md
```

第五步：

向我簡短說明：

```text
1. 準備沿用哪些 PrjAGWms Pattern
2. 準備重用哪些 DependencyWeb 邏輯
3. 新 DB Schema
4. Actor / Model / Controller 結構
5. GitHub → Graphify → LLM → Test Report Pipeline
6. 第一階段準備修改／建立哪些檔案
```

完成上述分析後，直接開始 Phase 1 實作。

除非遇到真正無法從既有專案、程式碼或設定判斷的必要資訊，否則不要反覆詢問我細節。
