# 關聯文件管理系統 (DependencyWeb)

這是一個用於管理和分析 Rails 專案中 Management Pages、Action Pages 和 Model 關聯的 Web 應用程式。系統可以從 GitHub 自動分析專案結構，或透過 CSV 檔案手動匯入資料。

### 🌐 網頁介面功能

1. **關聯文件主頁**
   - 顯示所有已匯入的專案（Company）
   - 點擊專案卡片可查看詳細資訊
   - 提供「GitHub 專案匯入」功能按鈕

2. **GitHub 專案匯入**
   - 透過網頁表單直接從 GitHub 匯入專案
   - 自動分析專案中的 Actors 和 Models 關聯
   - 不需要下載整個專案，直接透過 GitHub API 讀取檔案
   - 支援指定分支（預設：master）

3. **專案詳細頁面**
   - 顯示專案的所有 Management Pages
   - 顯示每個 Management Page 下的 Action Pages
   - 顯示 Action Pages 關聯的 Models
   - 支援搜尋功能
   - 支援篩選「異動檔案」（有 changed_flag 標記的檔案）

### 🔧 Rake Tasks 功能

#### 1. 程式碼分析

從 GitHub 分析專案，輸出關聯類別與方法：

```bash
# 使用預設值（AMASTek 組織下的多個專案）
rails code_analysis:relations

# 指定 Owner
OWNER=amashrm rails code_analysis:relations

# 指定多個 Repositories
REPOS=PrjJieZhou,PrjNO,HRM-BE rails code_analysis:relations

# 指定分支
BRANCH=develop rails code_analysis:relations

# 完整範例
OWNER=AMASTek REPOS=PrjJieZhou,PrjNO BRANCH=main rails code_analysis:relations
```

#### 2. GitHub PR 分析

分析 GitHub Pull Request 的檔案變更並更新 flag 標記：

```bash
# 使用預設值
rails github_analysis:update_flags

# 指定參數
rails github_analysis:update_flags[AMASTek,PrjJieZhou,65,PrjJieZhou]

# 顯示 flag 狀態統計
rails github_analysis:show_stats[PrjJieZhou]

# 重置所有 flag 狀態
rails github_analysis:reset_flags[PrjJieZhou]

# 測試 GitHub API 連線
rails github_analysis:test_connection[AMASTek,PrjJieZhou,65]

# 列出可用的 PR
rails github_analysis:list_prs[AMASTek,PrjJieZhou]
```

#### 3. CSV 匯入

從 CSV 檔案匯入 Management Pages 和 Action Pages：

```bash
# 匯入指定公司的資料
company=PrjJieZhou rails import:company
```

CSV 檔案應放置在 `lib/assets/` 目錄下，檔名格式為 `{company}.csv`

CSV 檔案應包含以下欄位：
- `管理頁面(management_pages)`
- `商業邏輯(action_pages)`
- `關聯邏輯(relate_action)`
- `關聯模組(relate_model)`
- `使用欄位(select_column)`
- `異動欄位(modify_column)`
- `刪除記錄(delete_column)`

#### 4. 開發工具

```bash
# 重建資料庫（清除、建立、遷移、匯入）
rails dev_func:rebuild

# 執行測試
rails dev_func:test_app

# 建立 API 文件
rails dev_func:build_api

# 檢查程式碼風格
rails dev_func:check_style

# 執行完整的程式碼品質分析
rails dev_func:code_analysis
```

## 環境設定

### GitHub Token（Rails credentials）

GitHub 相關功能會從 **Rails encrypted credentials** 讀取權杖，而非一般環境變數。請執行 `EDITOR="code --wait" bin/rails credentials:edit`（或你慣用的編輯器）並加入：

```yaml
github_classic_token: ghp_xxxxxxxx   # 建議：GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
github_access_token: ghp_xxxxxxxx    # 選填：僅在未設定 github_classic_token 時作為後備（舊鍵名）
```

應用程式會**優先使用** `github_classic_token`，未設定時才使用 `github_access_token`。

### 安裝步驟

1. 安裝依賴套件：
```bash
bundle install
yarn install
```

2. 設定資料庫：
```bash
rails db:create
rails db:migrate
rails db:seed
```

3. 啟動伺服器：
```bash
rails server
```

或使用 Foreman（如果使用 Procfile.dev）：
```bash
foreman start -f Procfile.dev
```

## 使用方式

### 方式一：透過網頁介面匯入 GitHub 專案

1. 開啟瀏覽器，前往首頁（通常是 `http://localhost:3000`）
2. 點擊右上角的「➕ GitHub 專案匯入」按鈕
3. 填寫表單：
   - **Owner**: GitHub 使用者或組織名稱（預設：AMASTek）
   - **Repository**: 專案名稱（預設：PrjJieZhou）
   - **分支名稱**: 分支名稱（選填，預設：master）
4. 點擊「開始匯入」按鈕
5. 等待匯入完成，系統會自動跳轉回主頁

### 方式二：透過 Rake Task 匯入

使用 `code_analysis:relations` task 從命令列匯入：

```bash
rails code_analysis:relations
```

### 方式三：透過 CSV 檔案匯入

1. 準備 CSV 檔案，放置在 `lib/assets/` 目錄
2. 執行匯入指令：
```bash
company=PrjJieZhou rails import:company
```

## 專案結構

### 主要模型

- **Company**: 代表一個專案/公司
- **ManagementPage**: 管理頁面
- **ActionPage**: 商業邏輯/動作頁面
- **RelateModel**: 關聯的 Model

### 主要 Actor（業務邏輯）

- `CodeAnalysis::ImportFromGithub`: 從 GitHub 匯入專案
- `CodeAnalysis::RelationsFromGithub`: 分析 GitHub 專案的關聯
- `CodeAnalysis::CollectActionClassesFromGithub`: 收集 Action Classes
- `CodeAnalysis::CollectModelClassesFromGithub`: 收集 Model Classes
- `CodeAnalysis::AnalyzeManagementPagesFromGithub`: 分析 Management Pages
- `CodeAnalysis::ImportToDatabase`: 匯入資料到資料庫

### 主要服務

- `GithubAnalysisService`: GitHub API 相關服務
- `FlagUpdateService`: Flag 更新服務

## 注意事項

1. **GitHub API Token**: 必須在 credentials 設定 `github_classic_token`（或後備的 `github_access_token`）才能使用 GitHub 相關功能
2. **API 限制**: GitHub API 有速率限制，大量匯入時請注意
3. **分支名稱**: 如果專案使用 `main` 而非 `master`，請在匯入時指定正確的分支名稱
4. **CSV 編碼**: CSV 檔案應使用 UTF-8 編碼


