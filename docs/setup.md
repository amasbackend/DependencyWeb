# Setup

How to get this app running locally, and what a real deployment needs. See `docs/system_architecture.md` for what the pieces actually do; this file is just the checklist.

## 1. `bundle install`

```bash
bundle install
```

Ruby 3.1.4, Rails 7.1.2. Notable gems (not defaults from `rails new`): `service_actor`/`service_actor-rails` (Actor pattern), `blueprinter`, `enumerize`, `octokit` (GitHub API), `solid_queue` (background jobs), `faraday` (LLM HTTP clients), `dotenv-rails` (dev/test only).

## 2. Database setup

Two databases, configured in `config/database.yml`:

- **`primary`** (MySQL 5.7+, `mysql2` adapter) — all domain data. Credentials come from Rails encrypted credentials, **not** `ENV`:
  ```bash
  bin/rails credentials:edit
  ```
  Set `database_host`, `database_username`, `database_password`. (This is the one exception to this project's "GitHub/LLM secrets go in `ENV`" rule — see `docs/architecture_plan.md` §16 for why DB credentials specifically stay on Rails' own convention.)
- **`queue`** (SQLite, local file under `storage/`) — Solid Queue's own tables only. MySQL 5.7 doesn't support `SKIP LOCKED`, which Solid Queue's dispatcher requires, so this is a separate connection even though `primary` is otherwise the database for everything.

Create and migrate both:

```bash
bin/rails db:create db:migrate
```

`db:migrate` runs both `db/migrate` (primary) and `db/queue_migrate` (queue) automatically per `config/database.yml`'s `migrations_paths`.

## 3. GitHub Token

```bash
# .env (development/test — git-ignored, loaded by dotenv-rails)
GITHUB_ACCESS_TOKEN=ghp_...
```

In production, set `GITHUB_ACCESS_TOKEN` as a real environment variable instead (`dotenv-rails` is dev/test only — see Gemfile). Needs at least `repo` scope (read) for any repository the app will import, including private ones — cloning goes through `git` directly (`GIT_ASKPASS`-based auth, not a plain URL-embedded token), not just the GitHub API.

Never hardcode, log, or store this token in the database (§64/§66) — it's read lazily via `GithubConfig.access_token` (`config/initializers/github_definition.rb`) only when an actor actually needs it, so boot/migrate/test runs never fail just because it's unset.

## 4. Graphify

Graphify is a **Python CLI** (package `graphifyy`, requires Python ≥3.10), not a Ruby gem — install it via [`uv`](https://astral.sh/uv), not `pip`/`pipx`, since `uv` manages its own isolated Python version and needs no root access:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install graphifyy
```

This installs the `graphify` binary to `~/.local/bin`. `config/initializers/graphify_definition.rb` prepends that directory to `ENV["PATH"]` at boot if it exists and isn't already on `PATH` — this matters because whatever process actually runs the background worker (systemd, Docker entrypoint, etc.) may not source the same shell profile an interactive login does. Verify it's reachable:

```bash
bin/rails runner 'puts GraphifyCli.version'
```

If this raises `GraphifyCli::NotInstalled`, the binary isn't on `PATH` for the Rails process specifically (check with `which graphify` in the *same* shell/user Rails actually runs as).

## 5. LLM Provider

Pick one of three vendors — switching is a config change, never a code change (`app/services/llm/provider.rb`):

```bash
LLM_PROVIDER=gemini          # or: openai | claude | claude_cli (no key — uses the logged-in `claude` CLI's claude.ai seat; see docs/commands.md)
GEMINI_API_KEY=...           # or: OPENAI_API_KEY | ANTHROPIC_API_KEY, matching the provider above
LLM_MODEL=gemini-2.5-flash   # optional — each provider has a built-in default (see LlmConfig::DEFAULT_MODELS)
TEST_SCOPE_PROMPT_VERSION=v1 # optional, defaults to "v1" — bump when the prompt itself changes, so historical
                              # TestReport rows stay attributable to the prompt version that produced them
```

Same rules as the GitHub token: never hardcoded, never logged, never stored in the database, never rendered into HTML or an exception message (§33). If unset, any actor that reaches `Llm::Provider.current` raises a clear `Unsupported LLM_PROVIDER`/`KeyError` — not a silent fallback to a different provider.

**No real LLM traffic in the automated test suite** (§68) — every provider test stubs Faraday's own test adapter with realistically-shaped canned responses. A missing API key never breaks `bin/rails test`.

## 6. Background Worker

Every PR analysis (Git diff → Graphify → impact mapping → LLM → report rendering) runs as one Solid Queue job (`PullRequestAnalysisJob`) — nothing in this pipeline runs synchronously inside a web request. The worker process must be running for PR analyses (and project imports) to ever actually complete:

```bash
bin/jobs
```

`config/queue.yml` configures one worker pool (`queues: "*"`, `JOB_CONCURRENCY` env var to scale worker processes, default 1) and a dispatcher polling every 1s. In development, `bin/dev` (if present) or running `bin/jobs` alongside `bin/rails server` in a second terminal both work; in production, run `bin/jobs` as its own supervised process (systemd unit, Docker service, etc.) alongside the web server — killing it doesn't crash the app, it just means nothing ever leaves `queued`.

## 7. Server

```bash
bin/rails server
```

Boots and serves `GET /up` (200) even with `GITHUB_ACCESS_TOKEN`/`GEMINI_API_KEY`/DB credentials completely unset — every secret access is lazy. Actually *using* the app (importing a project, analyzing a PR) obviously needs the real values from steps 2-5.

`config.time_zone = "Asia/Taipei"` (`config/application.rb`) — reports and timestamps display in UTC+8 regardless of server locale; storage stays UTC.

## Quick end-to-end smoke test

Once all of the above is done:

```bash
bin/rails runner '
  actor = Projects::Create.result(owner: "AMASTek", repository_name: "PrjJieZhou")
  puts actor.success? ? "queued project #{actor.project.id}" : actor.error
'
```

Then, with `bin/jobs` running, watch `project.status`/`analysis_status` advance to `ready`, and `Project → 分析 PR → <PR number>` on the web UI to run a full PR analysis. See `project_plan.md` §78 for the full acceptance walkthrough this should satisfy end to end.
