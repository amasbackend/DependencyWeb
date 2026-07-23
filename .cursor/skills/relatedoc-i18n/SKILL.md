---
name: relatedoc-i18n
description: >-
  Completes and maintains zh-TW I18n (model.yml, actor.yml, controller.yml) for RelateDoc
  QA business views. Use frontend navbar/Vue/view labels as source of truth. Use when
  fixing English leftovers in management_pages QA view, LocaleParser gaps, or preparing
  PR impact / QA reports for any imported GitHub project.
---

# RelateDoc I18n

為 **RelateDoc（關聯文件／PR 影響／QA 業務視圖）** 維護各母專案 `config/locales/zh-TW/`。  
中文用詞以 **該專案前端實際顯示**（`app/views/**/_navbar.html.erb`、Vue、ERB）為準，不以英文 class 名直譯。

## When to apply

- 新增／修改 Model 欄位、Actor、Controller flash
- RelateDoc 業務視圖出現英文欄位名／空白 module_label／英文權限 key／英文操作名
- 使用者要求補 I18n 或稽核 QA 畫面英文殘留

## Files to touch（母專案 repo）

| 檔案 | RelateDoc 用途 | 內容 |
|------|----------------|------|
| `config/locales/zh-TW/model.yml` | H5/H6＋操作／權限 | models、attributes、menu、perm_module、**perm_action**、**operation_type**、state |
| `config/locales/zh-TW/actor.yml` | Actor 訊息 | `actor.*` |
| `config/locales/zh-TW/controller.yml` | Flash／權限 | 各 namespace |

不要改 DependencyWeb 內 locale；補母專案 yml 後經 `LocaleParserService` 匯入。

## 分支約定

1. 在母專案建立 `test/i18n` 分支：`git checkout -b test/i18n`
2. locale 修改只提交到該分支
3. RelateDoc「同步 GitHub 母資料」分支填 `test/i18n`

## Workflow

```
I18n Progress:
- [ ] 1. 對照 schema／前端用詞（navbar、Vue label、表頭）
- [ ] 2. 更新 model.yml（含 perm_action／operation_type）
- [ ] 3. 更新 actor.yml（若有 Actor 訊息）
- [ ] 4. 更新 controller.yml（若有 flash）
- [ ] 5. QA 英文殘留稽核（掃描 actors + permission_check）
- [ ] 6. RelateDoc 重新同步母資料
```

### operation_type 通用後綴（禁止併譯）

| key | 中文 | 說明 |
|-----|------|------|
| create / new | 新增 | |
| update | 編輯 | |
| list | 列表 | ≠ 查詢 |
| find / show | 檢視 | ≠ 查詢 |
| search | 查詢 | 權限／搜尋語意 |
| destroy / delete | 刪除 | |
| archive | 封存 | ≠ 刪除 |
| import / export | 匯入／匯出 | |
| start / stop | 開始／結束 | |
| finalize / sold | 定稿／成交 | 依專案語意 |

業務專用 Actor 葉名稱（如 `per_produce_time`）須依前端 label 另補 `operation_type` key。

### 掃描補漏

```bash
# Actor 葉名稱
find app/actors -name '*.rb' ! -path '*/concerns/*' -printf '%f\n' | sed 's/\.rb$//' | sort -u

# 權限 token
grep -RhoE 'permission_check\(\s*["'\''][^"'\'']+["'\''],\s*["'\''][^"'\'']+["'\'']' app/controllers | sort -u
```

### QA 欄位對應

| QA 欄 | 應寫入 model.yml |
|-------|------------------|
| 分組標題 | `menu.*` 或 `activerecord.models.*` |
| 操作（藍字） | `operation_type.<snake_suffix>` |
| 權限 | `perm_module.*` + `perm_action.*` |
| 欄位名 | `activerecord.attributes.<model>.*` |

## RelateDoc locale 消費

| 區塊 | 匯入 | 顯示 |
|------|------|------|
| activerecord.models / attributes | ✅ | ✅ |
| perm_module / perm_action | ✅ | ✅ |
| operation_type / menu | ✅ | ✅ |

locale 已寫入 yml 但 QA 仍英文 → 確認已 re-sync；或檢查 DependencyWeb helper／parser。

## 禁止

- 不以英文 class 名直接當顯示文案
- 不刪除仍被程式使用的舊 typo key，應並存正確 key
- 不要只補 CRUD 而漏業務 Actor 葉名稱

## Additional resources

- RelateDoc 規格：`docs/PR_IMPACT_REFACTOR_PLAN.md`
- 現有 locale：`config/locales/zh-TW/`（各母專案）
