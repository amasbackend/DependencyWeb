# 常用指令

日常開發用的指令速查表。第一次建置環境請看 `docs/setup.md`；這份文件是「環境已經建好之後，平常怎麼操作」。

## 啟動服務

```bash
PORT=3099 bin/dev
```

3000 port 常被這台機器上其他服務佔用，習慣上都用 3099。`bin/dev` 透過 `Procfile.dev` 同時跑三個程序：`web`（Rails server）、`css`（Tailwind 即時編譯）、`jobs`（背景工作，PR 分析/專案匯入都靠這個跑完，一定要有）。跑完後開 `http://127.0.0.1:3099`，或用這台機器的區網 IP（例如 `http://192.168.26.124:3099`）從別的裝置連——兩種都可以。

### 背景故事：為什麼要用區網 IP 才連得到（`ERR_CONNECTION_REFUSED`）

`Procfile.dev` 的 `web` 這行帶了 `-b 0.0.0.0`。原因：Rails 的 `bin/rails server` 在 development 環境**預設把 `-b/--binding` 設成 `localhost`**（這是 Rails 自己 `server_command.rb` 寫死的行為，不是 `config/puma.rb` 能蓋掉的——`config/puma.rb` 裡也加了 `bind "tcp://0.0.0.0:..."`，但透過 `bin/rails server` 啟動時這行完全沒用，因為 Rails CLI 層的 Host 設定會蓋掉它）。只綁 `localhost` 就代表只有這台機器自己用 `127.0.0.1`/`localhost` 連得到，不管是這台機器的區網 IP、還是其他裝置，一律 `ERR_CONNECTION_REFUSED`。**修法**：`-b 0.0.0.0` 明確告訴 Rails CLI 綁所有介面，這樣區網 IP 才連得到。

### 背景故事：`jobs` 啟動時偶發 `SQLite3::BusyException: database is locked`

`config/database.yml` 的 `queue_default`（Solid Queue 專用的 SQLite）原本沒有設 `timeout`，實測 `PRAGMA busy_timeout` 預設是 **0**——代表任何一次寫入衝突都會立刻報錯，完全不等待重試。`bin/dev` 啟動時 `jobs` 會 fork 出 Supervisor/Dispatcher/Worker 三個獨立程序，幾乎同時把自己的資料寫進 `solid_queue_processes` 表，SQLite 對「多個獨立程序同時寫」本來就處理得差，一撞上就直接炸掉。**修法**：`queue_default` 加了 `timeout: 5000`（5 秒），讓寫入衝突時用等的、不要立刻報錯。

### 背景故事：`css` 這行為什麼不是直接用 `bin/rails tailwindcss:watch`

之前這台機器上 `tailwindcss:watch` 會讓 `bin/dev` 整個掛掉（Bun runtime crash / foreman 一個程序死掉就全部關掉），根因已經查出來並修掉了，記錄在這裡以免以後又被搞混：

1. **Tailwind v4 的 watch 模式預設會遞迴監看 `--cwd` 底下的「每一個」目錄**（不只 view/CSS 檔）。這個專案的 `tailwindcss-rails` gem 呼叫 CLI 時沒有帶 `--cwd`，預設就是 Rails root——裡面 `tmp/cache/bootsnap/` 一項就有 ~2,700 個檔案、~270 個子目錄，全部都會被裝上 inotify watch，把這個沙盒環境的 inotify 資源用到爆掉，讓底層的 Bun runtime segfault 或吐 `inotify_add_watch ... No space left on device`。**修法**：`bin/tailwindcss-watch`（取代 `bin/rails tailwindcss:watch`）用 `--cwd app` 把監看範圍限縮到 `app/`——本來就是唯一可能出現 Tailwind class 的地方，這是正確的做法，不只是繞過這台機器的權宜之計。同時在 `app/assets/tailwind/application.css` 加了 `@source not` 排除 `tmp/`/`log/`/`storage/`/`vendor/`/`.git/`（這個主要是給「內容掃描」用的，watch 範圍實際上是靠 `--cwd` 控制，兩個要一起設才完整）。
2. **`tailwindcss --watch`（不加 `always`）在 stdin 被關閉時會自動停止 watch、乾淨結束（exit 0）**——這是 CLI 自己文件寫的行為（`--watch[=always]`）。互動式 shell 裡 stdin 通常還開著，所以直接手動跑感覺一切正常；但 foreman 不會保留一個活著的 stdin 給子程序，所以 `css` 程序幾乎立刻自己結束，foreman 預設「一個程序結束就把全部關掉」，連本來沒事的 `web` 也被拖下去關掉。**修法**：`bin/tailwindcss-watch` 用 `-w always`，不會因為 stdin 關閉就停。

如果之後又遇到 `bin/dev` 莫名其妙全部一起關掉、`css.1 | exited with code 0` 之類的 log，先看是不是這兩個原因又發生（例如換了一個更大的 gem 快取目錄、或哪個地方不小心把 `-w always` 改回 `-w`）。

### 背景故事：大型 PR（上百個檔案）分析在 LLM 這一步失敗

實測過兩種完全不同的失敗模式，根因都跟「PR 太大」有關，但表現方式不一樣：

1. **Gemini：`401 Expected OAuth 2 access token`**，看起來像金鑰錯誤，但金鑰其實是對的——直接拿同一把金鑰打 API 重現過，第一次 `429 quota exceeded`，幾秒後重試就成功。真正原因是免費額度的 rate limit，而 `app/services/llm/provider.rb` 原本把所有 4xx（含 429）都當「重試也沒用」直接放棄，完全沒有等待重試。已修：429 現在會重試（`BACKOFF_SECONDS * 嘗試次數` 的等待時間，最多 `MAX_ATTEMPTS` 次）。這個修法對「小 PR 只是恰好撞到瞬間額度」有效，但救不了下面第 2 種。
2. **OpenAI：`429 Request too large ... tokens per min (TPM): Limit 30000, Requested 123294`**——這是真正的硬限制：單一請求需要的 token 數本身就超過整個帳號每分鐘的額度，不管重試幾次、等多久都沒用。根因是 `Llm::TestScopeInputBuilder` 原本沒有任何大小上限，一個 121 個檔案、369 個 impact items 的 release PR 會組出約 490KB（~12 萬 token）的 prompt。已修：`MAX_IMPACT_ITEMS`（依 `ImpactItem::RISK_ORDER` 優先保留 direct_change/direct_dependency，砍掉證據較弱的 indirect_dependency/regression_candidate）+ `MAX_FILES_WITH_PATCH`（只有改動量最大的檔案附上 patch 片段，其餘檔案保留 metadata 但不附 patch）。砍掉的項目數量會寫進 prompt 裡明確告訴 LLM（見 `TestScopePrompt#omitted_note`），不會靜默漏掉也不會讓 LLM 自己編代號引用。用實際的 PR #89（121 檔案）驗證過：prompt 從 ~490KB 降到 ~95KB（~2.4 萬 token），GPT/Gemini 都能穩定跑完。

如果之後遇到 LLM 分析步驟報 429 或逾時，先看是哪一種：`401`/`429 quota exceeded` 字樣通常是額度問題（等待重試或加值）；`Request too large`/`tokens per min` 字樣是單一請求太大，要調小 `MAX_IMPACT_ITEMS`/`MAX_FILES_WITH_PATCH` 才會有用，加值或換供應商都救不了。

### 手動重新編譯 Tailwind CSS

平常 `bin/dev` 開著的話不需要，watcher 存檔就會自動重編。要手動編一次的話：

```bash
bin/rails tailwindcss:build
```

## 停止服務 / 清乾淨重開

```bash
# 找出目前在跑的
cat tmp/pids/server.pid          # web server 的 pid
ps aux | grep -E "puma|solid_queue" | grep -v grep

# 停止（用實際查到的 pid，不要用 pkill 打 pattern —— 這台機器上 pkill 對這幾個
# 程序常常抓不準、或誤報失敗，用 kill <pid> 直接點名最可靠）
kill <server_pid>
kill <jobs_supervisor_pid>

# 清掉殘留的 pidfile，不然下次 bin/rails server 會誤判「已經在跑了」而拒絕啟動
rm -f tmp/pids/server.pid
```

**確認 Solid Queue 真的有停/有起來**（比看 log 有沒有報錯更準，因為它是背景 fork 出來的子程序，`ps`/`pkill` 常常抓不到正確的程序名稱）：

```bash
bin/rails runner 'SolidQueue::Process.order(:created_at).each { |p| puts "#{p.kind} pid=#{p.pid} heartbeat=#{p.last_heartbeat_at}" }'
```

如果同時看到兩組不同 pid、heartbeat 時間差很多的 process，代表舊的那組沒有真的被殺掉，要手動用 `kill -9 <pid>` 清掉，避免兩組背景工作程序同時搶著處理同一份 job。

## 測試

```bash
bin/rails test                                  # 全部（不含 test/system）
bin/rails test test/services/llm/                # 整個目錄
bin/rails test test/models/project_test.rb        # 單一檔案
bin/rails test test/models/project_test.rb:42     # 單一檔案裡指定行號的那個 test
bin/rails test:system                             # system test（需要真的 Chrome，這台機器目前沒有裝）
```

## 資料庫

```bash
bin/rails db:migrate                    # primary + queue 兩個資料庫的 migration 都會跑（見 config/database.yml）
RAILS_ENV=test bin/rails db:migrate     # test 資料庫也要記得同步 migrate
bin/rails db:rollback                   # 回滾最後一個 migration
bin/rails db:schema:dump                # 手動重新產生 db/schema.rb（一般 migrate 會自動做）
```

## Rails Console / 一次性腳本

```bash
bin/rails console                       # 互動式
bin/rails runner 'puts Project.count'   # 跑一段程式後直接結束，適合腳本化檢查
```

常用檢查片段：

```ruby
# 確認 LLM 金鑰真的能打通（會真的打一次 API，不是 stub）
Llm::Provider.current.generate(prompt: "Reply with exactly the word: OK")

# 確認 GitHub Token 有效
GithubClient.build.user.login

# 確認 Graphify CLI 裝好了
GraphifyCli.version
```

## 環境變數 / 金鑰（`.env`，開發環境用，git-ignored）

| 變數 | 用途 | 必要性 |
|---|---|---|
| `GITHUB_ACCESS_TOKEN` | 匯入/同步 GitHub 專案、抓 PR | 必要 |
| `LLM_PROVIDER` | `gemini`（預設） / `openai` / `claude` / `claude_cli` | 選填 |
| `GEMINI_API_KEY` / `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | 對應 `LLM_PROVIDER` 選的那家 | 必要（LLM 分析步驟要用；`claude_cli` 不需要）|
| `CLAUDE_CLI_PATH` | `claude_cli` 用的 `claude` 執行檔路徑（預設 `claude`，即 PATH 上的那支）| 選填 |
| `LLM_MODEL` | 覆蓋預設模型 | 選填，見下 |
| `LLM_TEMPERATURE` | 覆蓋預設溫度（預設不送，維持各家原本行為）| 選填 |
| `LLM_EFFORT` | 僅 `claude_cli`：`low` / `medium` / `high` / `xhigh` / `max`，傳給 `claude --effort`（預設不送，維持 CLI 原本行為）| 選填 |

**`claude_cli`** 不打 HTTP API，而是在背景執行 `claude -p`（Claude Code CLI），用的是該 CLI 登入的 claude.ai 帳號額度（Pro/Max/Team 席位的使用上限），不是 API 計費。執行 Rails 的那個 OS 使用者必須先 `claude` 登入過，可用 `claude auth status` 確認 `authMethod` 是 `claude.ai`。子程序會移除 `ANTHROPIC_API_KEY`，避免 CLI 偷偷改用 API key 計費。預設模型是 `claude-opus-5-5`（`LLM_MODEL` 對所有 provider 都生效，所以只想改 CLI 的模型時改 `DEFAULT_MODELS`），報告裡記錄的是 CLI 回報的完整模型名稱。CLI 不支援 `LLM_TEMPERATURE`，會被忽略。

**目前 Gemini 預設模型是 `gemini-3.6-flash`**（`config/initializers/llm_definition.rb`）——`gemini-2.5-flash` 已被 Google 下架，2026-08-27 用真實金鑰測試時撞到過，已經修掉。LLM 模型名稱會隨時間被官方汰換，如果哪天又打 API 撞到 `404 no longer available`，去看錯誤訊息裡官方指名的替代型號，改 `DEFAULT_MODELS` 或用 `LLM_MODEL` 覆蓋掉。

檢查目前 `.env` 裡設了哪些 key（不印出實際內容）：

```bash
grep -oE "^[A-Z_]+=" .env
```

## Graphify（分析程式碼依賴圖用的 CLI，非 Ruby gem）

```bash
which graphify           # 確認裝了
uv tool install graphifyy # 沒裝的話這樣裝
```

## 快速煙霧測試（確認整條流程沒斷）

```bash
bin/rails runner '
  actor = Projects::Create.result(owner: "AMASTek", repository_name: "PrjJieZhou")
  puts actor.success? ? "queued project #{actor.project.id}" : actor.error
'
```

跑完後要 `bin/jobs` 開著，才會真的處理完（匯入 / PR 分析都是背景工作，不會卡在 web request 裡跑完）。
