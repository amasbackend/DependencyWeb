---
name: relatedoc-i18n
description: >-
  Completes and maintains zh-TW I18n (especially model.yml) so any Rails-like project
  can be imported with Chinese labels for menus, models, attributes, permissions,
  operations, and states. Adapts discovery to actors/services/controllers/SPA menus.
  Use frontend labels as source of truth. Use when preparing test/i18n for sync/import.
---

# 專案 zh-TW I18n（匯入用・通用版）

本 Skill 用於**目前這個專案**產出可被外部關聯／QA／測試清單工具匯入的中文 locale。  
適用多種 Rails 架構（有／無 Actor、Service Object、純 Controller、Vue／SPA 選單等）。

**產出契約固定；掃描路徑依專案實際結構調整。**  
中文用詞以**前端實際顯示**為準，不要用英文 class／檔名直譯。

## When to apply

- 準備推上 `test/i18n` 供外部工具同步匯入
- 新增功能後補譯、或稽核英文 key／併譯
- 任何需要「一份可匯入 model.yml」的 Rails 子專案

---

## 第一步：專案偵察（先做再寫 yml）

先判斷本專案屬於哪些型態（可複選），再選對應掃描策略。**不要假設一定有 `app/actors`。**

| 偵測到 | 代表型態 | 模組／操作 key 主要從哪來 |
|--------|----------|---------------------------|
| 存在 `app/actors/<folder>/` | Actor 分層 | 資料夾名＝模組；檔名葉＝操作 |
| 存在 `app/services/` 或 `app/interactors/` | Service／Interactor | 類名葉 `.underscore`＝操作；目錄／namespace＝模組 |
| 主要邏輯在 `app/controllers/` | 傳統 MVC | controller 路徑／resource＝模組；action＝操作 |
| 有 `permission_check`／`authorize`／CanCan／Pundit／自訂 ACL | 權限系統 | 掃實際呼叫的 module／action token |
| 有 `_navbar*`／sidebar／menu Vue | 有導覽 | 葉節點中文優先；模組 key 對齊路由／權限 |
| 幾乎無 ERB、前端在 `app/javascript` 或獨立 frontend | SPA／API | 從 routes、OpenAPI、前端 router／i18n 對照 |

寫下偵察結果（給自己的 checklist）：

```
Project shape:
- [ ] actors / services / interactors / controllers-only / mixed
- [ ] permission style: permission_check / pundit / cancan / other / none
- [ ] menu source: _navbar ERB / Vue router / other
- [ ] models: ActiveRecord schema 是否存在
```

---

## 匯入端只認這個檔（契約）

匯入端**只抓第一個存在的檔**（不合併多檔）：

| 優先序 | 路徑 |
|--------|------|
| 1 | `config/locales/zh-TW/model.yml` ← **匯入譯文請集中寫這裡** |
| 2 | `config/locales/zh-TW.yml` |

根節點：`zh-TW:`（建議）。

**不會匯入** `actor.yml`、`controller.yml`、前端自己的 i18n JSON 等——那些只服務本專案執行期，**不能取代 `model.yml`**。

同一次匯入還可能掃（有就有、沒有就跳過）：

| 路徑 | 用途 |
|------|------|
| `app/views/**/_navbar*` | 選單葉中文 |
| `app/controllers/**/*_controller.rb` | 權限 token、入口對應 |
| `config/routes.rb` | 路由／註解 |
| `app/actors/**`（若存在） | 管理頁／操作結構 |

→ 因此：**即使專案沒有 Actor，仍必須產出完整 `model.yml`**；結構分析可能較少，但譯文檔格式相同。

---

## 必須寫入的七大區塊（所有專案共通）

| YAML 路徑 | 匯入用途 | Key 怎麼定（通用規則） |
|-----------|----------|------------------------|
| `activerecord.models` | Model／模組中文 | **snake_case** model 或業務模組名 |
| `activerecord.attributes` | 欄位中文 | `<model_snake>.<column>`（巢狀 key **禁止 PascalCase**） |
| `menu` | 管理頁／分組標題 | 與「匯入後的管理頁 name」相同：有 actors 用資料夾名；否則用 routes／controller 資源名／前端模組 id |
| `perm_module` | 權限模組中文 | 權限系統的 **module token**（字串原樣） |
| `perm_action` | 權限動作中文 | 權限系統的 **action token**（字串原樣） |
| `operation_type` | 操作名稱 | 操作葉名稱 `.underscore`（只取最後一段，如 `Create`→`create`） |
| `state` | 狀態中文 | `<model_snake>.<state>`（有 enum／狀態機就補） |

### 最小可匯入骨架（任何專案先產出這個）

```yaml
zh-TW:
  activerecord:
    models: {}
    attributes: {}
  menu: {}
  perm_module: {}
  perm_action: {}
  operation_type: {}
  state: {}
```

再依偵察結果填滿；空 hash 可匯入但畫面會英文 fallback。

### 完整示意（範例 key 請換成「本專案掃到的真實 key」）

```yaml
zh-TW:
  activerecord:
    models:
      order: 訂單
      customer: 客戶
    attributes:
      order:
        serial: 訂單編號
        customer_id: 客戶
        status: 狀態
      customer:
        name: 名稱

  menu:
    order: 訂單管理
    customer: 客戶管理

  perm_module:
    order: 訂單
    customer: 客戶

  perm_action:
    list: 列表
    find: 檢視
    show: 檢視
    search: 查詢
    create: 新增
    new: 新增
    update: 編輯
    edit: 編輯
    destroy: 刪除
    delete: 刪除
    archive: 封存
    import: 匯入
    export: 匯出
    # 專案自訂 token 一律補上

  operation_type:
    list: 列表
    find: 檢視
    show: 檢視
    search: 查詢
    create: 新增
    new: 新增
    update: 編輯
    destroy: 刪除
    delete: 刪除
    archive: 封存
    import: 匯入
    export: 匯出
    start: 開始
    stop: 結束
    schedule: 排程
    sign: 簽核
    cancel: 取消
    finish: 完成
    sync: 同步
    finalize: 定稿
    sold: 成交
    copy: 複製
    # 業務專用葉（必補）：
    # approve: 核准
    # assign_driver: 指派司機

  state:
    order:
      pending: 待處理
      paid: 已付款
      cancelled: 已取消
```

---

## Key 對齊總則（跨架構）

1. **Key = 程式裡的穩定識別字**，不是中文拼音、不是顯示名。  
2. **顯示名 = YAML 的 value**，來自前端用詞。  
3. 同一業務概念若有多個 token（`edit` 與 `update`），**兩邊都寫**，不要只寫一個。  
4. `operation_type` 只取操作葉的 underscore：  
   - `Orders::Create` / `Order::Create` / `CreateOrder`（若匯入端以最後一段為準）→ 優先確認匯入命名；**有 Actor 時以 `::` 最後一段**為準（`create`）。  
   - 業務葉 `AssignDriver` → `assign_driver`（不可省略）。  
5. `attributes` 的 model 層必須 snake_case：`order` 不是 `Order`。  
6. 禁止併譯：`list`≠`find`≠`search`；`archive`≠`destroy`。

---

## 依專案型態：從哪裡掃 key

### A. 模組／選單 → `menu` + `models` +（常一併）`perm_module`

**有 `app/actors` 時（優先）：**

```bash
find app/actors -mindepth 1 -maxdepth 1 -type d ! -name concerns -printf '%f\n' | sort
```

每個資料夾名 → `menu.<name>`、建議同時 `activerecord.models.<name>`、`perm_module.<name>`。

**無 actors、有 controllers／routes：**

```bash
# resources / namespaces
grep -E '^\s*(namespace|resources|resource)\b' config/routes.rb | head -n 100
ls app/controllers | sed 's/_controller\.rb$//' | sort
```

用 **resource／controller 路徑的最後一段 snake_case** 當 `menu` key（與前端模組 id 對齊）。

**前端選單（所有型態都要對）：**

| 來源 | 找什麼 |
|------|--------|
| `app/views/**/_navbar*`、`*sidebar*`、`*menu*` | `name:`／`text:` 中文；連結對應的 module key |
| `app/javascript/**/*.{js,vue,ts}`、`**/router/**` | 選單 title、route meta.title |
| 既有 locale／i18n JSON | 可複用中文，但**仍要抄進 model.yml** |

有 `_navbar` 時：葉節點請維持使用者看到的中文（匯入會直接吃）；模組層標題仍靠 `perm_module`。

### B. 操作 → `operation_type`

**有 actors：**

```bash
find app/actors -name '*.rb' ! -path '*/concerns/*' -printf '%f\n' | sed 's/\.rb$//' | sort -u
```

檔名／類名葉 → snake_case 寫入 `operation_type`。

**有 services／interactors：**

```bash
find app/services app/interactors -name '*.rb' 2>/dev/null | xargs -n1 basename | sed 's/\.rb$//' | sort -u
```

對每個會被 controller／job 呼叫、且代表「使用者可做的一件事」的類，取葉名 underscore。

**純 MVC：**

- 每個對外 `def` action（`index/show/create/update/destroy` 及自訂）→ 對應 `operation_type`  
- `index` 常對 `list`；`show` 常對 `find`／`show`（以本專案用詞與權限 token 為準，**兩邊 token 都補**）

**業務專用篩選（有 actors 時）：**

```bash
find app/actors -name '*.rb' ! -path '*/concerns/*' -printf '%f\n' \
  | sed 's/\.rb$//' \
  | grep -viE '^(create|update|list|find|show|destroy|new|archive|import|export|start|stop|search|delete|edit|copy|sync|cancel|finish|sign|schedule|finalize|sold)$' \
  | sort -u
```

無 actors 時：對 services／自訂 controller actions 做同樣「非 CRUD 名單」人工補譯。

### C. 權限 → `perm_module` + `perm_action`

依實際權限 API 掃（**不要只假設 `permission_check`**）：

```bash
# 常見：permission_check("module", "action")
grep -RhoE 'permission_check\(\s*["'\''][^"'\'']+["'\''],\s*["'\''][^"'\'']+["'\'']' app/controllers app/actors app/services 2>/dev/null | sort -u

# Pundit／自訂 authorize
grep -RnE 'authorize\b|permit\?\(|can\?\(|cannot\?' app/controllers app/policies 2>/dev/null | head -n 80

# CanCan ability
grep -RnE 'can :|cannot :' app/models/ability.rb app/abilities 2>/dev/null | head -n 80
```

規則：

- 掃到的 **module 字串** → `perm_module.<token>`
- 掃到的 **action 字串** → `perm_action.<token>`
- 若專案無獨立權限系統：仍建議用 menu／resource 名當 `perm_module`，CRUD 當 `perm_action`，避免匯入後權限欄全空

### D. 欄位 → `activerecord.attributes`

| 來源 | 適用 |
|------|------|
| `db/schema.rb`／migrate | 有 DB 的專案（優先） |
| `app/models/**/*.rb` | enum、alias、關聯 |
| serializers／GraphQL types／API schema | API-first |
| 表單 ERB／Vue 表頭 | 用詞來源 |
| 既有 `config/locales/**` | 複用，但抄進 `model.yml` |

優先補：列表、表單、匯出、會被業務操作讀寫的欄位（含 `_id`）。

### E. 狀態 → `state`

- `enum`、AASM、state_machines、status 欄位  
- 畫面上的狀態標籤／篩選器  

無狀態機可留空 `state: {}`，但有就要補。

### F. 本專案執行期（選做，匯入不讀）

- `config/locales/zh-TW/actor.yml`／`controller.yml`／前端 i18n  
- 可與 `model.yml` 用詞一致，但**匯入驗收只看 model.yml**

---

## 通用操作／權限對照（禁止併譯）

| key | 中文 | 注意 |
|-----|------|------|
| create / new | 新增 | |
| update / edit | 編輯 | |
| list | 列表 | ≠ 查詢 |
| find / show | 檢視 | ≠ 查詢 |
| search | 查詢 | |
| destroy / delete | 刪除 | |
| archive | 封存 | ≠ 刪除 |
| import / export | 匯入／匯出 | |
| start / stop | 開始／結束 | |
| schedule / sign / cancel / finish / sync / copy | 排程／簽核／取消／完成／同步／複製 | |
| finalize / sold | 定稿／成交 | 依產業語意可改，但 key 保留 |

表外每個業務操作 key 都必須有獨立譯文。

---

## AI 執行流程（通用）

```
I18n Progress:
- [ ] 0. 專案偵察（actors/services/MVC、權限、選單來源）
- [ ] 1. 建立或開啟 config/locales/zh-TW/model.yml（七大區塊齊）
- [ ] 2. 依型態掃出模組 key → menu + models + perm_module
- [ ] 3. 依型態掃出操作 key → operation_type（含非 CRUD）
- [ ] 4. 依權限 API 掃 token → perm_module + perm_action
- [ ] 5. 依 schema／表單／API → attributes（snake_case）
- [ ] 6. 依 enum／狀態 UI → state
- [ ] 7. 對齊前端用詞（navbar／Vue／按鈕／表頭）；有 _navbar 則葉文案維持中文
- [ ] 8. 自檢：無併譯；業務葉無英文殘留；attributes 無 PascalCase model key
- [ ] 9. 提交到 test/i18n 並 push
```

## 分支約定

1. `git checkout -b test/i18n`（若尚無）  
2. locale 只提交到 `test/i18n`  
3. 匯入端同步分支填 `test/i18n`

## 禁止

- 假設所有專案都有 `app/actors` 或 `permission_check`（先偵察）
- 只寫本專案執行期 locale、不寫 `model.yml`
- 英文 class／檔名當顯示文案；list／find／search／archive 併譯
- 刪除仍在使用的舊 typo key（並存）
- `attributes` 用 `Order` 這種 PascalCase 當巢狀 key

## 完成檢查（跨專案）

### 檔案契約

- [ ] `config/locales/zh-TW/model.yml` 存在且含七大區塊
- [ ] 變更在 `test/i18n`

### 內容覆蓋

- [ ] 每個「會出現在匯入管理頁／選單」的模組都有 `menu`（或 models／perm_module 後備）
- [ ] 每個使用者可執行的操作葉都有 `operation_type`
- [ ] 每個權限 module／action token 都有 `perm_*`（若專案有權限）
- [ ] 主要 model 欄位有 `attributes`
- [ ] 有狀態則有 `state`
- [ ] list≠find≠search；archive≠destroy

### 用詞

- [ ] value 與前端一致（非直譯）
- [ ] 同義 token（edit/update、find/show）皆已覆蓋

### 型態適配自檢

- [ ] 已依實際目錄選對掃描命令（不是照抄 actors-only）
- [ ] 無 actors 時仍用 routes／controllers／services 填滿同一契約
