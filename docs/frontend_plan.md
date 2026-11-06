# 任務：為目前 GitHub PR 測試範圍分析系統規劃完整前端重構與跨 LLM 一致性架構

目前你位於這個 Rails 專案的根目錄。

請進入 **Plan / Analysis 模式**。

本階段：

> **先完整閱讀現有專案、理解資料流與畫面，再提出完整重構計畫。**

不要立即大規模修改程式。

不要先憑空建立新的 Frontend Framework。

不要因為目前畫面簡陋就直接導入 React / Vue / Tailwind / Bootstrap。

應先確認目前 Rails 專案實際使用：

* ERB
* Turbo
* Stimulus
* Importmap
* Propshaft / Asset Pipeline
* SCSS / CSS
* Bootstrap / Tailwind
* JavaScript bundler
* 其他既有前端方案

再決定最適合此專案的實作方式。

---

# 一、目前系統定位

這個系統的核心不是一般 Git Viewer。

它的目的為：

```text
GitHub Repository
        ↓
Rails Code Index
        ↓
Business Feature
        ↓
GitHub PR
        ↓
Git Diff
        ↓
Graphify
        ↓
Dependency Analysis
        ↓
LLM Analysis
        ↓
操作人員測試範圍
```

系統同時服務兩種角色。

## 1. 操作／測試人員

主要需要知道：

```text
這次改到什麼功能？

我要去哪個頁面？

從哪個選單進去？

要操作什麼？

輸入什麼？

按什麼？

看到什麼結果才算正常？

哪些功能需要回歸？
```

---

## 2. 工程師

主要需要知道：

```text
哪些檔案被修改？

哪些 Controller / Actor / Model 被修改？

Graphify 找到哪些 Dependency？

哪些功能是 Direct Impact？

哪些是 Indirect Impact？

為什麼系統判斷需要測這個功能？
```

---

因此 UI 必須清楚區分：

```text
業務視圖
技術視圖
```

而不是把所有資訊混在同一頁。

---

# 二、先閱讀目前專案

首先找出並閱讀：

```text
config/routes.rb

app/controllers/**
app/models/**
app/actors/**
app/services/**

app/views/**
app/helpers/**

app/javascript/**
app/assets/**
app/components/**

config/locales/**

db/schema.rb

spec/**
test/**
```

另外特別找出：

```text
Project
BusinessModule
BusinessFeature
CodeEntity

PullRequestAnalysis
ChangedFile
Impact
GraphifyArtifact
TestReport
TestCase

LLM Provider
LLM Skill
Prompt
Report Builder
```

相關實作。

不要只依名稱判斷。

追蹤實際資料流。

---

# 三、先建立「目前系統畫面 → 程式碼」對照

目前至少已存在以下頁面。

---

## A. 首頁

目前包含：

```text
GitHub PR 測試範圍分析

GitHub 專案匯入

Owner
Repository
Advanced Option

已匯入專案

同步母分支
刪除
```

---

## B. Project Detail

目前包含：

```text
Project Name

Owner
母分支
Base SHA
狀態
最後同步

同步 GitHub 母資料

搜尋

業務視圖
技術視圖

Business Module
Business Feature
```

---

## C. Project Technical View

目前已經可以看到：

```text
功能名稱

Controller
Controller Action
File Path
```

等技術關聯。

---

## D. PR Analysis

目前包含：

```text
PR Number

狀態

PR Title

Base
Head

Base Branch Warning

修改檔案數量
受影響技術實體
受影響業務功能
```

以及 Tabs：

```text
測試範圍
修改內容
業務視圖
技術視圖
Graphify
Raw Diff
```

---

## E. Graphify

目前主要直接顯示：

```text
Graphify Raw JSON
```

這不是最終使用者應看到的 Graphify UX。

---

## F. Raw Diff

目前主要顯示：

```text
git diff
```

功能正確，但缺乏 Diff Viewer 的可讀性。

---

# 四、目前 UI 的主要問題

根據現有畫面與程式碼確認以下問題是否成立。

不要直接假設，請逐項檢查。

目前明顯可能存在：

```text
1. 大量 Browser Default Style

2. 資訊階層不明顯

3. 專案列表仍是 ul/li

4. Business Feature 仍是純文字列表

5. Technical Relation 太難掃描

6. PR Summary 缺乏視覺層級

7. Graphify 直接顯示 Raw JSON

8. Raw Diff 缺少 Code Diff UX

9. 操作人員路徑不夠明確

10. Business / Technical Context 沒有清楚串起來

11. Detail 資訊一次全部鋪在頁面

12. 缺少 Hover / Expand / Drill Down

13. 缺少 Sticky Toolbar / Filter

14. 缺少 Status Badge

15. 缺少 Loading / Empty / Failed State

16. 缺少整個網站一致的 Design System
```

先確認後再納入 Plan。

---

# 五、此次前端重構的核心方向

必須完成以下五個主要方向。

---

# 方向 1：全面表格化

大量資訊改為：

```text
Table
+
Expandable Row
+
Filter
+
Search
+
Status Badge
```

而不是：

```text
ul
li
p
br
```

堆疊。

---

# 六、首頁重新設計

首頁定位為：

> Project Dashboard

而不是單純匯入表單。

---

## 頂部

設計：

```text
GitHub PR 測試範圍分析
────────────────────────────────────────

[＋ 匯入 GitHub 專案]

專案總數     Ready     分析中     Failed
    6          5          0          1
```

---

## GitHub Project Import

不要讓 Import Form 永遠佔首頁大量空間。

可以考慮：

```text
Modal

Drawer

Expandable Card
```

形式。

主要輸入：

```text
Owner
Repository
```

Advanced：

```text
Branch Override
其他必要設定
```

---

# 七、專案列表改為完整 Data Table

目前：

```text
AMASTek/PrjJieZhou
母分支
狀態
最後同步

同步
刪除
```

改為例如：

| 專案                 | 母分支    | Base SHA | 功能數 | Graphify | 狀態    | 最後同步        | 操作 |
| ------------------ | ------ | -------- | --: | -------- | ----- | ----------- | -- |
| AMASTek/PrjJieZhou | master | 5968f02  | 108 | Ready    | Ready | 08/19 00:43 | ⋯  |

Base SHA 顯示 shortened SHA。

Hover 完整 SHA。

---

# 八、Project Row Hover

滑鼠 Hover 整列時：

```text
背景變化
Row Elevation 或 Border
Quick Action 顯示
```

例如：

```text
[查看]
[PR 分析]
[Graphify]
[同步]
```

但不要造成過多動畫。

動畫以：

```text
120ms ~ 200ms
```

微互動為主。

---

# 九、Project Row Expand

點：

```text
⌄
```

展開：

```text
Repository
Default Branch
Base SHA

Business Module 數
Business Feature 數
Code Entity 數

最近 PR
最後 Graphify
最後同步

Repository Status
Analysis Status
```

避免所有資訊全部放主 Table。

---

# 十、Project Detail Page 重新設計

Project Page 頂部建立：

```text
AMASTek / PrjJieZhou

master
Ready
Last Sync 2026-08-19 00:43

[同步母分支]
[分析 PR]
[開啟 Graphify IDE]
```

---

## 第二層 Navigation

使用：

```text
Overview
業務功能
技術實體
PR 分析
Graphify IDE
```

不要讓所有內容全部出現在同一頁。

---

# 十一、Business Feature Table

Business Feature 是 Project Page 最重要內容之一。

改為 Data Table。

例如：

| 模組     | 功能       | 操作人員路徑        | Route                   | Controller | Actor  | Model      | Graph |
| ------ | -------- | ------------- | ----------------------- | ---------- | ------ | ---------- | ----- |
| CNC 機台 | CNC 機台列表 | 系統設定 → CNC 機台 | `/setting/cnc_machines` | index      | List   | CncMachine | 12    |
| 工單     | 更新工單     | PMS → 工單 → 編輯 | `/api/pms/...`          | update     | Update | WorkOrder  | 8     |

---

# 十二、業務視圖預設隱藏技術細節

操作人員預設只看到：

```text
模組
功能
操作路徑
操作說明
狀態
```

Controller / Actor / Model 等資訊：

放到 Expand Detail。

---

# 十三、Expandable Business Feature

點某一列：

```text
CNC 機台列表
```

展開：

```text
業務資訊
────────────────────────

功能：
CNC 機台列表

操作人員路徑：

系統設定
  → CNC 機台
  → CNC 機台列表


實際 URL：

/setting/cnc_machines


使用者可以：

查看機台
搜尋機台
查看機台詳細資料


技術依據
────────────────────────

Route:
GET /setting/cnc_machines

Controller:
Setting::CncMachinesController#index

Actor:
CncMachine::List

Model:
CncMachine


Graphify
────────────────────────

Upstream: 3
Downstream: 8

[在 Graphify IDE 開啟]
```

---

# 十四、操作人員視角「路徑」必須重新定義

現在最需要改善的不是 URL。

而是：

> 人實際如何走到該功能。

例如不要只顯示：

```text
/workstation/a3_order/:work_date
```

應該顯示：

```text
生產管理
→ A3 工作站
→ 選擇工作日期
→ 選擇工單
→ 冷卻
```

URL 可以作為：

```text
Technical Detail
```

保留。

---

# 十五、Operator Path Evidence

「操作人員路徑」不能讓 LLM 自己幻想。

建立證據來源優先級。

優先讀：

```text
Navigation
Menu

Sidebar
Breadcrumb

Route

View Page Title

Button Text

Link Text

i18n

Controller

Action
```

---

# 十六、操作路徑建立規則

例如：

```text
Navigation：
生產管理

Link：
A3 工作站

Page：
A3 生產

Button：
冷卻
```

則推導：

```text
生產管理
→ A3 工作站
→ 工單
→ 冷卻
```

---

如果沒有足夠證據：

```text
操作路徑：需要人工確認
```

禁止讓 LLM 自行補一條看起來合理但不存在的路徑。

---

# 十七、Operator Path 需要 Evidence

資料結構應能保存：

```text
path_segment
source_type
source_file
source_text
confidence
```

例如：

```json
{
  "label": "冷卻",
  "source_type": "view_link",
  "source_file": "app/views/...",
  "confidence": 1.0
}
```

---

# 十八、Hover 設計

整站建立一致 Hover 行為。

---

## Table Row

Hover：

```text
背景變淡
Border Accent
Cursor pointer
顯示 Quick Action
```

---

## Business Feature

Hover 功能名稱：

Tooltip：

```text
操作路徑：
PMS → 工單 → 編輯

Controller:
...

Actor:
...
```

---

## Code Entity

Hover：

```text
Class
Path
Type

Direct dependencies
Indirect dependencies
Mapped Features
```

---

## Graph Node

Hover：

```text
Node Name
Type
File
Business Feature
Dependency Count
```

並 Highlight：

```text
Inbound Edge
Outbound Edge
```

---

# 十九、Graphify 不再只顯示 Raw JSON

目前 Graphify Tab 主要直接顯示：

```text
graph_json
nodes
edges
```

Raw JSON 可以保留。

但應移到：

```text
Advanced
→ Raw Graphify JSON
```

---

# 二十、每個 Project 建立自己的 Graphify IDE

Project Detail 增加：

```text
Graphify IDE
```

Route 可以類似：

```text
/projects/:project_id/graph
```

實際 route 依目前 Rails 設計決定。

---

# 二十一、Graphify IDE Layout

設計成三欄 IDE。

```text
┌─────────────────────────────────────────────────────────┐
│ PrjJieZhou Graphify IDE                       Search     │
├──────────────┬──────────────────────────┬───────────────┤
│ Explorer     │                          │ Inspector     │
│              │                          │               │
│ Business     │                          │ Node          │
│ Controller   │        GRAPH             │ Type          │
│ Actor        │                          │ File          │
│ Model        │                          │ Feature       │
│ View         │                          │ Dependencies  │
│              │                          │               │
├──────────────┴──────────────────────────┴───────────────┤
│ Filters / Path / Selected Node                          │
└─────────────────────────────────────────────────────────┘
```

---

# 二十二、Graphify IDE 左側 Explorer

顯示：

```text
Business Module
Business Feature

Controller
Actor
Model
View
Job
Concern
```

可：

```text
Collapse
Expand
Search
Filter
```

---

# 二十三、中間 Graph Canvas

必須提供：

```text
Node
Edge

Zoom
Pan
Fit

Center Selection

Reset

Filter
```

Node Type 要有視覺差異。

例如：

```text
Business Feature
Controller
Actor
Model
View
```

但不要過度使用十幾種顏色。

---

# 二十四、Graph Hover

Hover Node：

```text
目前 Node 突出

直接 Parent Highlight
直接 Child Highlight

其他 Node opacity 降低
```

讓 Dependency Path 一眼可見。

---

# 二十五、Graph Click

Click Node 後右側 Inspector：

```text
WorkOrder::EstimatedCompletion

Type:
Actor

File:
app/actors/work_order/estimated_completion.rb

Business Feature:
預估完成日

Direct Inbound:
5

Direct Outbound:
3

Indirect:
18

[查看程式資訊]
[查看業務功能]
[只看上游]
[只看下游]
```

---

# 二十六、Graph Business Feature Mode

除了技術 Node Mode，加入：

```text
Business Mode
```

例如：

```text
工單建立

   ↓

預估完成日

   ↓

排程

   ↓

生產加工
```

Business Mode 用 Feature Relationship。

Technical Mode 才看：

```text
Controller
Actor
Model
```

---

# 二十七、PR Graph Overlay

從 PR Analysis 點：

```text
在 Graphify IDE 開啟
```

時可以帶入：

```text
PR Analysis ID
```

Graph 顯示：

```text
Changed
Direct Impact
Indirect Impact
Unaffected
```

不同狀態。

---

# 二十八、PR Analysis Page 全面重構

目前 PR Page 已有很好的資訊骨架。

保留：

```text
測試範圍
修改內容
業務視圖
技術視圖
Graphify
Raw Diff
```

但重新設計資訊階層。

---

# 二十九、PR Header

例如：

```text
PR #113
Hotfix - 修正完成日計算方式 #5106

Completed

Base
release3.1.3

Head
hotfix/estimated_completion/#5106
```

右側：

```text
2 Changed Files

1 Technical Entity

3 Business Features

Medium Risk
```

---

# 三十、Branch Warning

目前已有：

```text
PR Base Branch 與目前母分支不同
```

保留。

但改為 Warning Alert。

例如：

```text
⚠ Base Branch 不一致

此 PR：
release3.1.3

目前 Project：
master

本次分析使用 PR 實際 Base SHA。
```

---

# 三十一、測試範圍 Tab

這是預設 Tab。

先顯示：

```text
修改摘要

核心影響

回歸範圍

測試案例
```

---

# 三十二、測試案例改成 Table

例如：

| 風險     | 模組 | 功能    | 操作路徑          | 驗證目的    | 類型         |
| ------ | -- | ----- | ------------- | ------- | ---------- |
| High   | 工單 | 預估完成日 | PMS → 工單 → 詳細 | 確認完成日計算 | Direct     |
| Medium | 工單 | 加工中工單 | PMS → 生產      | 回歸計算    | Regression |

---

# 三十三、展開 Test Case

點擊後：

```text
測試資料準備

操作路徑

操作步驟

預期結果

失敗判讀

相關 Regression

分析依據
```

---

# 三十四、分析依據預設收起

一般操作人員不需要看到：

```text
Changed Actor
Graphify Node
Diff
```

所以放：

```text
▶ 為什麼需要測？
```

展開才顯示：

```text
Changed:
WorkOrder::EstimatedCompletion

Changed Method:
total_production_speed

Graphify:
...

Mapped Feature:
預估完成日
```

---

# 三十五、測試報告格式統一

報告仍以「操作人員／測試人員」為主要讀者。

最終至少包含：

```text
修改摘要

操作頁面 ↔ 驗證目的

測試前準備

各模組測試步驟

預期結果

失敗判讀

測試通過標準

建議測試順序

操作人員回報資訊
```

---

# 三十六、Raw Diff Viewer

不要再純：

```text
<pre>
git diff
</pre>
```

規劃 Code Diff Viewer。

---

## File Header

例如：

```text
app/actors/work_order/estimated_completion.rb

+7
-3

Modified
```

---

## Diff

提供：

```text
Line Number

Added
Removed

Collapsed Context
```

---

## Changed File List

左側或上方：

```text
2 Changed Files

▾ app/actors/...
▸ spec/actors/...
```

點擊跳到該 File。

---

# 三十七、修改內容 Tab

改為結構化資訊。

例如：

| 類型    | Entity                         | Method                 | Change   | Feature |
| ----- | ------------------------------ | ---------------------- | -------- | ------- |
| Actor | WorkOrder::EstimatedCompletion | total_production_speed | Modified | 預估完成日   |

展開顯示 Diff。

---

# 三十八、技術視圖

例如：

| Type  | Name                           | File           | Change   | Direct | Indirect |
| ----- | ------------------------------ | -------------- | -------- | -----: | -------: |
| Actor | WorkOrder::EstimatedCompletion | app/actors/... | Modified |      5 |       18 |

點擊可以直接：

```text
Graphify IDE
```

定位。

---

# 三十九、全站 Design System

設計風格定位：

> 企業內部 Developer / QA Analysis Console

不要設計成：

```text
行銷網站
炫技 Dashboard
大量 Gradient
大量動畫
過度圓角
```

---

# 四十、視覺方向

建議：

```text
Neutral Background

White Surface

Blue / Indigo Accent

Green = success
Amber = warning
Red = error

Gray = technical secondary info
```

Status Color 只用在必要地方。

---

# 四十一、Typography

建立完整層級：

```text
Page Title

Section Title

Table Header

Body

Meta

Code

Badge
```

技術資訊：

```text
SHA
Route
Class
File
```

使用 monospace。

---

# 四十二、Spacing

建立固定 spacing token。

例如：

```text
4
8
12
16
24
32
```

不要讓每個 View 自己亂寫 margin。

---

# 四十三、UI Components

規劃 reusable components / partials。

例如：

```text
PageHeader

Breadcrumb

StatusBadge

MetricCard

DataTable

ExpandableRow

EmptyState

ErrorState

LoadingState

Tabs

SearchBar

FilterBar

Tooltip

CodeBadge

RiskBadge

OperatorPath

EvidencePanel

GraphInspector
```

依目前 Rails 前端架構決定使用：

```text
Partial
ViewComponent
Stimulus Controller
Helper
```

不要先假設一定使用 ViewComponent。

---

# 四十四、Responsive

主要使用環境明顯為 Desktop。

優先：

```text
1280
1440
1920
```

但：

```text
Laptop
Tablet
```

仍不能完全壞掉。

大量 Table 可以：

```text
horizontal scroll
sticky first column
```

而不是強迫塞成 Cards。

---

# 四十五、Accessibility

至少規劃：

```text
Keyboard Navigation

Visible Focus

ARIA for expand

Button != clickable div

Contrast

Tooltip 不只能靠 hover
```

---

# 四十六、最重要的第二部分：跨 LLM 一致性

目前系統未來可能使用：

```text
Claude
Gemini
OpenAI
```

甚至其他 Provider。

核心要求：

> Provider 可以不同，但分析契約必須相同。

---

# 四十七、禁止的架構

不要：

```text
Gemini Prompt A

Claude Prompt B

OpenAI Prompt C
```

三套各自生長。

否則最後一定會出現：

```text
Claude 判定 8 個功能

Gemini 判定 3 個功能

OpenAI 判定 15 個功能
```

而且報告格式完全不同。

---

# 四十八、建立 Canonical Analysis Pipeline

應統一為：

```text
Git Diff
   ↓
Diff Parser
   ↓
Graphify
   ↓
Relevant Code Extraction
   ↓
Business Feature Mapping
   ↓
Operator Path Evidence
   ↓
Canonical Evidence Pack
   ↓
Canonical Skill
   ↓
LLM Provider
   ↓
Structured JSON
   ↓
Schema Validator
   ↓
Report Renderer
```

---

# 四十九、LLM Provider 不負責分析規則

Provider：

```text
GeminiProvider
ClaudeProvider
OpenAiProvider
```

只應負責：

```text
API Call
Authentication
Retry
Timeout
Token Usage
Response Extraction
```

不要讓：

```text
GeminiProvider
```

自己決定測試分析規則。

---

# 五十、建立共用 Skill

例如：

```text
skills/
  test_scope_analysis/
```

或符合目前專案架構的地方。

包含：

```text
skill.md

input_schema.json

output_schema.json

report_rules.md

operator_perspective.md

evidence_rules.md
```

實際結構依目前專案決定。

---

# 五十一、所有 Provider 使用相同 Skill

Claude：

```text
Canonical Skill
+
Evidence Pack
→ Claude
```

Gemini：

```text
Canonical Skill
+
Evidence Pack
→ Gemini
```

OpenAI：

```text
Canonical Skill
+
Evidence Pack
→ OpenAI
```

不是三套不同 Prompt。

---

# 五十二、Canonical Evidence Pack

建立固定資料格式與順序。

例如：

```json
{
  "project": {},
  "pull_request": {},
  "changed_files": [],
  "changed_entities": [],
  "diff_summary": [],
  "graphify": {
    "direct_dependencies": [],
    "indirect_dependencies": []
  },
  "business_features": [],
  "operator_paths": [],
  "routes": [],
  "views": [],
  "i18n": []
}
```

---

# 五十三、Evidence Pack 必須 deterministic

所有 Provider 接收到的資料：

```text
欄位一致
順序一致
資料範圍一致
排序一致
```

避免：

Claude 得到 Actor 全文。

Gemini 只得到 Diff。

OpenAI 又得到整個 Repository。

---

# 五十四、Relevant Code Extraction 也必須共用

建立共用規則，例如：

```text
1. Changed File

2. Changed Method

3. Direct Dependency

4. First-Level Caller

5. Business Feature Entry Point

6. Relevant Route

7. Relevant View

8. Relevant i18n
```

所有 Provider 使用同一 Context Builder。

---

# 五十五、不要要求「相同隱藏思考過程」

不同 LLM 的內部推理不可被工程上可靠控制。

我們真正需要控制的是：

```text
相同 Input

相同 Skill

相同分析步驟要求

相同 Evidence

相同 Output Schema

相同 Validation

相同 Report Renderer
```

---

# 五十六、建立可驗證 Analysis Summary

LLM Output 可以包含：

```text
analysis_summary
```

例如：

```json
{
  "feature": "預估完成日",
  "impact_type": "direct",
  "reason": "修改的 Actor 直接參與此功能的完成日計算",
  "evidence_ids": [
    "diff:1",
    "graph:32",
    "feature:8"
  ]
}
```

這是：

```text
可驗證的判斷依據
```

而不是要求模型輸出完整內部 Chain-of-Thought。

---

# 五十七、Structured Output

所有 LLM 必須回傳同一 JSON Schema。

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

---

# 五十八、Test Case Schema

例如：

```json
{
  "module_name": "",
  "feature_name": "",
  "operator_path": [],
  "risk": "",
  "impact_type": "",
  "verification_goal": "",
  "preconditions": [],
  "steps": [],
  "expected_results": [],
  "failure_conditions": [],
  "evidence_ids": [],
  "confidence": 0.0
}
```

---

# 五十九、Report Format 不由 LLM 決定

這點非常重要。

LLM：

```text
JSON
```

Rails：

```text
JSON
↓
Report Renderer
↓
HTML
Markdown
```

因此：

Claude、Gemini、OpenAI 最後產出的報告：

```text
標題

Table

Section

順序

格式
```

完全一致。

---

# 六十、跨 LLM 一致性 Test

建立固定 Fixture。

例如：

```text
spec/fixtures/llm_analysis/pr_113/
```

保存：

```text
Evidence Pack
```

然後：

```text
Claude
Gemini
OpenAI
```

使用同一份資料分析。

比較：

```text
JSON Schema Compliance

Affected Feature Coverage

Operator Path

Direct / Indirect Classification

Test Case Count

Evidence Coverage

Unsupported Claims
```

---

# 六十一、一致性不是要求文字一模一樣

例如：

Claude：

```text
確認預估完成日是否正確計算
```

Gemini：

```text
驗證系統計算出的預估完成日期
```

這可以視為一致。

真正要一致的是：

```text
Feature

Impact

Operator Path

Test Intent

Expected Result

Evidence
```

---

# 六十二、增加 Analysis Metadata

每份結果保存：

```text
provider

model

skill_version

prompt_version

schema_version

evidence_hash

temperature

generated_at
```

---

# 六十三、低隨機性

如果 Provider 支援：

建議：

```text
temperature = 0 ~ 0.2
```

用於這種分析任務。

不要追求創造性。

---

# 六十四、Uncertainty

如果無法確認：

```text
Button
Operator Path
Business Rule
Expected Result
```

輸出：

```text
uncertain
```

或：

```text
需要人工確認
```

禁止自行幻想。

---

# 六十五、Skill 必須明確要求操作人員視角

Canonical Skill 必須寫清楚：

> 最終測試案例的主要讀者為現場操作／QA 人員，不是 Rails Engineer。

---

例如禁止：

```text
呼叫 WorkOrder::EstimatedCompletion
確認 other_producing_orders_for_total_speed
```

---

應該：

```text
進入工單頁面

建立或找到符合條件的工單

查看預估完成日期

確認完成日是否依目前加工中的工單正確計算
```

---

# 六十六、技術資訊只能當 Evidence

例如：

```text
Actor：
WorkOrder::EstimatedCompletion

Method：
total_production_speed
```

放在：

```text
分析依據
```

而不是主要測試步驟。

---

# 六十七、Skill Version

Skill 必須版本化。

例如：

```text
test_scope_analysis/v1
```

未來：

```text
v2
v3
```

才能比較報告差異。

---

# 六十八、前端也要顯示 LLM Metadata

PR Analysis 可以顯示：

```text
Generated by:
Claude Sonnet

Skill:
Test Scope v1

Evidence:
34 items
```

但放 Secondary Info。

---

# 六十九、未來 Provider Switch

理想架構：

```text
LLM_PROVIDER=claude
```

改成：

```text
LLM_PROVIDER=gemini
```

不應改：

```text
Skill
Input Builder
Schema
Report Builder
Frontend
```

只改 Provider。

---

# 七十、Plan 必須包含資料需求分析

目前 UI 要做到上述效果，很可能現有 DB 資料不足。

不要為了前端而讓 View 自己臨時計算。

請確認是否需要：

```text
operator_path

operator_path_segments

feature_evidence

graph_node

graph_edge

impact_type

risk

confidence

evidence_id
```

等資料。

---

# 七十一、但不要立即加 Migration

目前是 Plan 階段。

先說明：

```text
目前已有什麼

缺什麼

哪些可以 Runtime Calculate

哪些值得 Persist
```

再提出 Migration Plan。

---

# 七十二、效能

Project 可能有：

```text
數百 Business Features

數千 Code Entities

數千 Graph Nodes
```

因此 Plan 必須考慮：

```text
Pagination

Lazy Load

Graph Virtualization

Expandable Row Lazy Fetch

Search Index

N+1

Preload
```

---

# 七十三、Graph 不應一次 render 所有東西

Graphify IDE 應有：

```text
Scope

Module

Feature

Entity Type

Depth
```

例如：

```text
Depth 1
Depth 2
Depth 3
```

避免一開始 render 3000 Nodes。

---

# 七十四、URL State

重要 Filter / Tab 最好可以保存 URL。

例如：

```text
/projects/6?view=technical

/projects/6/graph?feature=123&depth=2

/pull_request_analyses/4?tab=graphify
```

方便：

```text
重新整理

分享

返回
```

仍保持相同視圖。

---

# 七十五、Loading / Empty / Error

每個頁面都規劃：

```text
Loading

Empty

Error

Ready
```

例如 Graphify 尚未產生：

不要顯示空白。

顯示：

```text
尚未建立 Graphify 分析

[開始建立]
```

---

# 七十六、Confirmation

危險操作：

```text
刪除 Project

重新分析

重新同步
```

需要適當 Confirmation。

同步不一定屬危險操作，不要過度 Confirmation。

---

# 七十七、Plan 階段需要實際產出的內容

請完成程式閱讀後，建立：

```text
docs/frontend_redesign_plan.md
```

---

內容必須包含：

---

## 1. Current State

列出：

```text
目前 Frontend Stack

Layout

Views

CSS

JS

Project Page

PR Page

Graphify Page

LLM Architecture
```

---

## 2. Problem Map

逐頁描述：

```text
現在怎麼呈現

問題

預計如何改善
```

---

## 3. Information Architecture

完整 Navigation：

```text
Projects

Project
  Overview
  Business Features
  Technical Entities
  PR Analyses
  Graphify IDE

PR Analysis
  Test Scope
  Changes
  Business
  Technical
  Graph
  Diff
```

---

## 4. Design System

規劃：

```text
Typography

Spacing

Color

Table

Button

Badge

Tabs

Tooltip

Expandable Row

Panel

Code
```

---

## 5. Page Wireframes

用 ASCII 或 Markdown 畫：

```text
Homepage

Project Detail

Business Feature

Technical View

PR Analysis

Graphify IDE

Raw Diff
```

---

## 6. Component Plan

列出：

```text
Partial / Component

Stimulus Controller

Helper

CSS
```

及 Responsibility。

---

## 7. Operator Path Architecture

說明：

```text
如何取得

如何保存

Evidence

Confidence

人工確認
```

---

## 8. Graphify IDE Architecture

說明：

```text
Graph Data

API

Frontend Library

Node Filter

Hover

Selection

Inspector

PR Overlay

Performance
```

如果需要引入 Graph Library：

請比較至少：

```text
Cytoscape.js

Sigma.js

D3

其他適合方案
```

並根據目前 Rails Stack 選一個。

不要只因熟悉度直接選。

---

## 9. LLM Consistency Architecture

完整描述：

```text
Evidence Builder

Canonical Skill

Provider Adapter

Structured Schema

Validator

Report Renderer

Versioning

Regression Test
```

---

## 10. Backend Changes

列出前端重構真正需要的：

```text
Model

Actor

Service

Controller

API

Blueprint

Migration
```

不要把所有需求都塞給 Frontend。

---

## 11. File Change Map

精確列出預計：

```text
Create
Modify
Delete
```

哪些檔案。

---

## 12. Implementation Phases

至少拆：

```text
Phase 1
Design System / Layout

Phase 2
Homepage

Phase 3
Project Business Table

Phase 4
Operator Path

Phase 5
Technical View

Phase 6
PR Analysis

Phase 7
Diff Viewer

Phase 8
Graphify IDE

Phase 9
Canonical LLM Skill

Phase 10
Cross-provider Consistency

Phase 11
Tests / Polish
```

---

# 七十八、每個 Phase 必須包含

```text
Goal

Files

Backend Changes

Frontend Changes

Tests

Acceptance Criteria
```

---

# 七十九、Acceptance Criteria

最終至少滿足：

### Homepage

```text
已匯入專案使用 Table 顯示。

可以 Hover。

可以 Expand。

可以快速進入：

Project
PR
Graphify。
```

---

### Project

```text
Business Feature 為 Table。

操作人員路徑清楚。

Technical Detail 可展開。

搜尋與 Filter 可用。
```

---

### Graphify

```text
不再只能看 JSON。

每個 Project 有自己的 Graphify IDE。

可以 Zoom / Pan / Search / Filter。

Hover 可以 Highlight Dependency。

Click 可以查看 Inspector。

可以由 Feature 追到 Code。

可以由 Code 反查 Feature。
```

---

### PR Analysis

```text
Test Scope 為預設。

測試案例表格化。

每筆可展開。

操作人員步驟為主要資訊。

Technical Evidence 預設收起。
```

---

### Diff

```text
Changed File 清楚。

新增 / 刪除清楚。

可快速跳檔案。
```

---

### LLM

無論：

```text
Claude
Gemini
OpenAI
```

都必須：

```text
讀取同一 Evidence Pack

使用同一 Skill

符合相同 JSON Schema

使用相同 Business Feature

使用相同 Operator Path Evidence

輸出相同 Report Structure
```

---

# 八十、最重要的設計原則

這次重構不是單純：

```text
「把畫面弄漂亮」
```

真正目標是：

```text
Code
↓
Dependency
↓
Business Feature
↓
Operator Path
↓
Test Scope
```

這條關係在畫面上必須變得：

```text
看得懂

查得到

展得開

追得回去

有證據
```

---

# 八十一、Plan 完成後先停止

完成：

```text
docs/frontend_redesign_plan.md
```

後：

不要立即開始全面修改。

先回報：

```text
1. 目前前端 Stack

2. 現有 UI 最大問題

3. 新 Information Architecture

4. Business Feature Table 設計

5. Operator Path 建立方式

6. Graphify IDE 技術方案

7. LLM Canonical Skill 架構

8. 預計新增／修改的核心檔案

9. 是否需要 DB Migration

10. Implementation Phase 順序
```

並指出：

```text
哪些地方你從目前 Code 可以確定

哪些地方是設計建議

哪些地方仍需要實作時驗證
```

完成這份 Plan 後停止，等待下一步實作指令。
