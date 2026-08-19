# Architecture Plan — GitHub PR Test-Scope Analyzer

> Written per `project_plan.md` §2, before any Phase 1 implementation code. Covers the required 16 sections. This document is the authoritative schema/architecture reference for all later phases; update it (per §76) whenever a later phase reveals a design problem here.

## Current status (checkpoint — 2026-08-19)

**Done: Phases 1-9 of the §75 roadmap**, committed as `3da4a33` ("Initial build: Phases 1-9..."). `pull_request_analyses.status` currently advances `queued → fetching_pr → diffing` and stops there — everything from `graphifying` on is unbuilt. Full per-phase detail (design rationale, real bugs found and fixed, real-data validation) is inline below, in numbered-section order; this block is just a fast map to it.

| Phase | What | Where to read more |
|---|---|---|
| 1 | Schema (12 tables), Actor/Blueprinter conventions, Solid Queue on its own SQLite DB | §4, §14 |
| 2 | GitHub project import (`Projects::Create`/`Import`) | §2 (DependencyWeb comparison) |
| 3 | Repo manager: bare/mirror clone, `git worktree`, `GitCommand` (GIT_ASKPASS auth) | §8 |
| 4 | Graphify integration — confirmed as a real headless CLI, not just an AI-IDE skill | §9 |
| 5 | Base code index via Graphify + Rails-directory classification | §3 (Base Code Index Population), §9 |
| 6 | Business module/feature naming: route comments → CRUD rules → LLM (only for genuinely custom actions) | §11 (Phase 6 subsection) |
| 7 | Project UI: home + show page, business/technical view toggle, search, sync/delete | §6, §13 |
| 8 | PR import: metadata + merge-base via GitHub API only, no git access | §10 |
| 9 | Git diff: merge-base-aware, `RubyDiffHunkScanner` for §28's structured per-method diff | §10 (Phase 9 implementation notes) |

**Not yet built**: Phase 10 (Graphify PR impact — first phase that actually needs a real PR worktree), 11 (business feature impact mapping), 12 (LLM test-scope generation — the `Llm::Provider` abstraction exists from Phase 6, but no prompt/schema work yet), 13 (test report rendering), 14 (UI polish), 15 (automated-test hardening pass).

**Standing facts worth knowing before touching this repo further**:
- Primary DB is MySQL 5.7 (shared server, `192.168.26.123`, credentials in Rails encrypted credentials — see §4's deviation note); Solid Queue's own tables are on a **separate local SQLite DB** because that MySQL version lacks `SKIP LOCKED`.
- `GITHUB_ACCESS_TOKEN` lives in `.env` (git-ignored, loaded by `dotenv-rails` in dev/test only), reused from `/home/micky/DependencyWeb`'s credentials with the user's go-ahead.
- Real target repo for live validation throughout: `AMASTek/PrjJieZhou` — imported as `Project` id 6 in this environment (19 business modules, 93 features, 1219 code entities from real data), with at least one real `PullRequestAnalysis` (PR #113) fully diffed.
- No LLM provider has a real API key configured yet — the LLM-inferred business-feature-naming path (Phase 6) and all of Phase 12 are only verified against stubbed responses so far. The user offered to stand in as the LLM for manual testing when that's next relevant.
- Every phase was validated with a **live run against real GitHub data**, not just fixture-based automated tests — this caught several real bugs fixture tests alone missed (a Git-version-specific auth mechanism failure in Phase 3, a hunk-header misattribution edge case in Phase 9). Worth continuing this practice for Phase 10+.

## 1. PrjAGWms 可參考的架構模式

This project follows `/home/micky/PrjAGWms`'s conventions rather than inventing a new architecture:

- **Actor pattern** via the `service_actor` gem. Actors live in `app/actors/<namespace>/<verb>.rb` (e.g. `ItemStock::Update`), declare `input :x` / `output :x`, and either implement `call`/named methods or compose other actors via `play ActorA, ActorB, :instance_method` (short-circuits on the first failure). Call with `.result(...)` from controllers and tests — this never raises, returns the actor instance, check `.success?` / `.error`. Call with `.call(...)` when nested inside another actor's `play`/method body — this raises internally and is caught automatically by the enclosing `play`. Failures always go through `fail!(error: "message")`, with message text sourced from `I18n.t("actor.<namespace>.<key>", ...)`.
- **Blueprinter** for all API/JSON serialization. `app/blueprints/<Model>::InfoBlueprint`, with multiple `view :xxx` blocks for different field sets (`:show`, `:list`, `:pair`, etc.), rendered via `SomeBlueprint.render_as_hash(records, view: :x)` from a small private controller helper. Controllers never hand-build JSON.
- **Thin, namespaced controllers**: each feature module gets a `<Namespace>::BaseController < ApplicationController`, and concrete controllers inherit from it (`Projects::ProjectsController < Projects::BaseController`). Controllers only run `before_action` permission/find checks, call exactly one Actor, and either assign `@ivars` for an HTML view or call `render_json(actor, data:)`.
- **Unified JSON envelope**: success → `{status: 0, message:, data:}`; failure → `{status: -1, message:, error: actor.error}`, with `actor.error` logged server-side via `logger.error` before rendering.
- **Transactions live inside Actor methods**, never in controllers or models: `Model.transaction do ... rescue StandardError => e; ErrorLogger.error(e.message); fail!(error: e.message) end`. External calls (GitHub API, git shell, Graphify, LLM) are never wrapped in a DB transaction — they get explicit Stage/Status tracking and resumable retry instead (see §11 Error Handling).
- **`enumerize`** gem (not plain Rails `enum`) backed by a single central `ModelEnum` registry class (`app/models/concerns/model_enum.rb`) — one classmethod per enum returning an ordered `{symbol: integer}` Hash — paired with `config/locales/zh-TW/enum.yml` for human-readable labels.
- **i18n split by concern, not by feature**: `config/locales/zh-TW/{actor,controller,model,enum}.yml`. Controllers use the implicit scoped lookup `t(".success")` / `t(".fail")`; actors always use a fully-qualified key.
- **Namespacing** is consistent across all four layers (model / actor / blueprint / controller) for a given domain concept.
- **Secrets**: PrjAGWms itself uses `Rails.application.credentials[:key]`. This project deliberately overrides that convention per `project_plan.md` §3, which explicitly mandates `ENV.fetch("GITHUB_ACCESS_TOKEN")`-style environment variables for GitHub/LLM secrets specifically. Frozen-constant + lazy-accessor modules in `config/initializers/` (mirroring PrjAGWms's "constants file per external concern" pattern, e.g. `system_definition.rb`) wrap the `ENV.fetch` calls.
- **Not adopted from PrjAGWms**: its `authenticate_user!`/session/`permission_check` auth machinery (this project has no auth requirement — building unused auth scaffolding would violate §72.9's "don't over-abstract"), SQL Server (this project uses MySQL for primary data — see §4), Vite+Vue3 frontend (this project keeps the existing importmap/Turbo/Stimulus scaffold — no SPA requirement here), RSpec (this project keeps Minitest, already scaffolded). PrjAGWms's *dual-database pattern* (a second `_shared_model` connection) is not reused for the same purpose, but this project ended up with its own two-database split for an unrelated reason — see §14.

**Database engine (deviation from the original Phase 1 plan)**: originally scaffolded on sqlite3 (the `rails new` default), then switched to **MySQL for primary application data** per explicit user instruction, mirroring `/home/micky/DependencyWeb`'s `config/database.yml` (`adapter: mysql2`, `encoding: utf8mb4`, `socket`/`host`/`username`/`password` structure, same shared MySQL 5.7.42 server at the credentials-configured host) — only the database names changed, to `dependency_web2_{development,test,production}`. One deliberate deviation from DependencyWeb's own config: its `test` and `production` environments point at the *same* database name (`relate`), which looks like a copy-paste bug rather than an intentional pattern (a test run against that config would wipe production data) — this project uses three distinct database names instead. DB credentials (`database_host`/`database_username`/`database_password`) are stored in Rails encrypted credentials (`config/credentials.yml.enc`), matching PrjAGWms/DependencyWeb's own convention for DB access — this is separate from the GITHUB_ACCESS_TOKEN/GEMINI_API_KEY secrets, which stay ENV-var-based per §3/§16 below (project_plan.md's explicit override applies specifically to those two, not to DB credentials).

`config/database.yml` is consequently a **two-database, multi-`connects_to` config** (`primary` + `queue`), not a single database — `ApplicationRecord` and every domain model use `primary` (MySQL) implicitly; only Solid Queue's own tables use `queue` (local SQLite). See §14 for why.

## 2. DependencyWeb 可重用的功能 ／架構問題

`/home/micky/DependencyWeb` is an existing but architecturally weaker sibling project. Per §0-B, code was reviewed for what's reusable, what's portable, and what has problems.

**Reused as concept (rewritten, not copied):**
- `DependencyGraphService`'s BFS multi-hop caller/callee graph traversal with depth limiting — a candidate for post-Graphify impact propagation if Graphify's own `graph.json` doesn't already provide multi-hop traversal.
- `ImpactAnalysisService`'s priority-ranked impact classification (direct > caller > callee > model_consumer/concern > caller_l2), persisted inside a transaction — this maps directly onto this project's `impact_items.impact_level` enum (§10).
- `TestScopeReportService` and its `DEFAULT_OPERATION_PLAYBOOK` — precedent for the *shape* of deterministic report generation, even though this project's report content is LLM-authored rather than Ruby-templated.
- The `ManagementPage → ActionPage → RelateModel` schema plus `EntryPoint`/`UiMenu`/`LocaleMetadata` — precedent for a technical-entity ↔ business-label mapping schema, informing this project's `CodeEntity`/`BusinessFeature`/`FeatureCodeEntity` design (§10).

**Explicitly NOT ported — confirmed architectural problems:**
- GitHub access is raw `Net::HTTP`, duplicated three times across `GithubRepoService`/`GithubAnalysisService` with no shared client, no auth-header centralization, no rate-limit/retry handling, and file-by-file/directory-by-directory recursive Contents-API crawling instead of a real clone. → This project uses `octokit` (§4) and does an actual `git clone`/bare-repo + worktree (§8), sidestepping the whole class of problem.
- All heavy work (GitHub crawl, PR analysis) runs synchronously inside controller actions — zero `ActiveJob` usage anywhere in that codebase. → This project backgrounds everything via Solid Queue from day one (§14).
- `CodeAnalysis::ImportToDatabase#call` does delete-then-recreate with **no transaction wrapper** — a partial-failure data-loss bug. → Every multi-step DB mutation in this project's actors is wrapped in `Model.transaction do ... end`.
- Hardcoded organization/repo/PR example defaults (`"AMASTek"`, `"PrjJieZhou"`, PR `"65"`) scattered through controllers, actors, and rake tasks. → Not carried over as code defaults (though the same values may still appear as example input in documentation/manual testing, since the user's own example project happens to be `AMASTek/PrjJieZhou`).
- `puts`-based logging of raw API response bodies and token-presence booleans in service classes. → This project uses structured Rails logging with a `[PRAnalysis:<id>]` correlation prefix (§16) and never logs response bodies or token values.
- No authentication on any controller. → Out of scope for this project too (no auth requirement in the spec), but noted as a known gap, not silently copied as "fine because the old app did it."

**Not present in DependencyWeb at all (100% greenfield for this project)**: git clone/worktree infrastructure, Graphify integration, LLM integration. Nothing to reuse or avoid for these — they are new designs (§8, §9, §10).

## 3. 新網站 Domain Model

Three layers, per `project_plan.md` §74 — kept strictly separate:

- **Layer 1 — Code**: `CodeEntity` (Model/Controller/Actor/Route/View/Method/File). Answers "what code changed?"
- **Layer 2 — Business Feature**: `BusinessModule` → `BusinessFeature` (e.g. 使用者 → 使用者列表/編輯使用者). Answers "what feature was touched?"
- **Layer 3 — Operator Test**: `TestReport` → `TestCase` (page, action, input, expected result, pass/fail). Answers "what does the operator actually need to test?"

Core relationships:
```
Project 1──N BusinessModule 1──N BusinessFeature
Project 1──N CodeEntity
BusinessFeature N──N CodeEntity  (through FeatureCodeEntity)
Project 1──N PullRequestAnalysis
PullRequestAnalysis 1──N ChangedFile
PullRequestAnalysis 1──N ChangedCodeEntity  (references ChangedFile, optionally CodeEntity)
PullRequestAnalysis 1──N GraphifyArtifact
PullRequestAnalysis 1──N ImpactItem  (references BusinessFeature, CodeEntity, ChangedCodeEntity)
PullRequestAnalysis 1──N TestReport 1──N TestCase  (references BusinessFeature, ImpactItem)
```

The data flow (§73): `GitHub → Rails Repository → Base Code Index → {Technical Entity, Business Feature} → Feature Mapping`, and separately per-PR: `PR Number → GitHub PR → Git Diff → Changed Code Entity → Graphify → Dependency Impact → Business Feature Impact → LLM → Operator Test Scope → Test Report`.

**Base Code Index population (Phase 5)**: `CodeEntity` rows are built by reusing Graphify (§9) rather than a separate hand-rolled Ruby parser — `Projects::IndexCode` runs `Graphify::Analyze` against an ephemeral worktree checked out at `project.base_sha`, then `CodeEntityExtractor` classifies each resulting graph node into a Rails `entity_type` purely by directory convention (`app/models/` → `model`, `app/controllers/` → `controller`, `app/actors/` → `actor`, etc. — see `CodeEntityExtractor::TYPE_BY_PATH_PREFIX`), since Graphify's tree-sitter extraction knows classes/methods/files but has no notion of Rails conventions itself. Two entity kinds Graphify can't produce are handled separately: **routes** (Graphify has no Rails routing-DSL awareness — a lightweight line-regex scan of `config/routes.rb` produces one `route`-type entity per `resources`/`resource`/HTTP-verb/`root` line, capturing the raw declaration text and line number; this is a deliberately shallow first pass — it does not resolve nested `namespace`/`scope` blocks into fully-qualified controller#action pairs, which would need a real Rails routing-DSL parse) and **views** (Graphify has no ERB/template-language support in its installed tree-sitter grammar set — every file under `app/views/**` becomes a file-level `view` entity with no class/method structure, matching how the spec's own examples reference views by file path alone, e.g. `users/edit.html.erb`). The scan is a full replace, not an incremental diff: `Projects::IndexCode` deletes the project's existing `code_entities` and bulk-inserts the freshly classified set inside one transaction, making re-scans (Phase 23 sync) idempotent without accumulating stale rows.

## 4. Database Schema

All 12 tables, MySQL-backed (mysql2 adapter, utf8mb4). Standard Rails `bigint` PKs/FKs. **JSON vs TEXT rule**: `json` columns hold payloads the app reads/writes as Ruby objects (parsed Graphify output, LLM structured JSON, evidence arrays, ordered step lists) — MySQL 8.0's native `JSON` column type gives real validation-on-write and `JSON_EXTRACT`/generated-column indexing if ever needed; `text` columns hold verbatim/opaque blobs the app stores but doesn't query into (raw Graphify CLI output, raw git patches, rendered Markdown), where a plain string is more appropriate than a JSON-validated column (some of these values, like rendered Markdown/HTML, aren't JSON at all).

### `projects`
| column | type | notes |
|---|---|---|
| owner | string, null: false | GitHub org/user; validated `\A[A-Za-z0-9_.\-]+\z` |
| repository_name | string, null: false | same validation |
| github_full_name | string, null: false, unique index | `"owner/repo"` — idempotency key for import |
| default_branch | string | from GitHub `repository.default_branch` |
| repository_path | string | **relative** path under `REPOSITORY_ROOT` — never an absolute path |
| base_sha | string | 母分支 SHA |
| last_synced_sha | string | |
| last_synced_at | datetime | |
| status | integer, default: 0, null: false, indexed | enumerize — coarse lifecycle (pending/importing/ready/syncing/failed) for the Project Card badge |
| analysis_status | integer, default: 0, null: false | enumerize — fine-grained current pipeline stage while status is importing/syncing |
| error_message | text | last failure, human-readable |
| created_at / updated_at | datetime | |

### `business_modules`
| column | type | notes |
|---|---|---|
| project_id | bigint, null: false, FK, indexed | |
| name | string, null: false | e.g. "使用者" |
| slug | string, null: false | idempotency key, unique per `[project_id, slug]` |
| description | text | |
| position | integer | stable UI ordering |
| source | integer, default: 0 | enumerize: locale_derived/route_derived/llm_inferred/manual — provenance, supports §15 "優先使用既有中文資訊" |
| created_at / updated_at | | |

### `business_features`
| column | type | notes |
|---|---|---|
| project_id | bigint, null: false, FK, indexed | denormalized for direct query without a join |
| business_module_id | bigint, null: false, FK | |
| name | string, null: false | e.g. "編輯使用者" |
| slug | string, null: false | idempotency key, unique per `[business_module_id, slug]` |
| domain_action | string | e.g. `"edit"`, `"cooling"`, `"scrap"` — the CRUD/domain verb driving §14's mapping rule |
| description | text | |
| position | integer | |
| source | integer, default: 0 | enumerize, same value set as `business_modules.source` |
| created_at / updated_at | | |

Risk level ("高風險/中風險/低風險", §43) is deliberately **not** a column — it's a property of a specific PR's impact on a feature, derived from `impact_items.impact_level` at report-render time, not a static feature attribute.

### `code_entities`
Technical Entity index (§16), rebuilt on every base-branch scan (§10, §23).

| column | type | notes |
|---|---|---|
| project_id | bigint, null: false, FK, indexed | |
| entity_type | integer, null: false, indexed (with project_id) | enumerize: model/controller/actor/service/blueprint/job/mailer/route/view/javascript/concern/validator/serializer |
| name | string, null: false | display name |
| class_name | string | |
| method_name | string | method-level granularity, needed by the diff parser (§28) |
| file_path | string, null: false, indexed (with project_id) | relative to repo root |
| line_start | integer | |
| line_end | integer | |
| namespace | string | |
| signature_hash | string, null: false | canonical hash of `(file_path, class_name, method_name)` — idempotency key, unique per `project_id`, survives line-number drift across re-scans |
| metadata | json | free-form extras (route verb+path, association info) — deliberately unstructured per §59 |
| created_at / updated_at | | |

### `feature_code_entities`
Reverse-impact join table (§17).

| column | type | notes |
|---|---|---|
| business_feature_id | bigint, null: false, FK | |
| code_entity_id | bigint, null: false, FK, indexed | this is the index the whole Impact Mapping pipeline pivots on: "PR touched code_entity X → which features?" |
| role | integer | enumerize: route/controller_action/actor/model/view/other — groups the §22 Technical View |
| source | integer, default: 0 | enumerize: rule_based/llm_inferred/manual — provenance, so a re-run of the mapping phase doesn't silently clobber manual curation |
| created_at / updated_at | | |

Unique index on `[business_feature_id, code_entity_id]`.

### `pull_request_analyses`
| column | type | notes |
|---|---|---|
| project_id | bigint, null: false, FK, indexed (with pr_number) | |
| pr_number | integer, null: false | |
| pr_title / pr_description / pr_author | string / text / string | |
| base_branch / base_sha | string | |
| head_branch / head_sha | string | |
| merge_base_sha | string | from `git merge-base` (§26) |
| status | integer, default: 0, null: false | enumerize — see §6 below |
| error_message | text | |
| error_stage | string | which stage failed — lets a retry resume from that stage (§51, §63) |
| workspace_path | string | relative worktree path (§6), cleared after cleanup |
| retry_count | integer, default: 0 | |
| started_at / finished_at | datetime | |
| created_at / updated_at | | |

`[project_id, pr_number]` is intentionally **not unique** — history must be kept (§19, §52); see §11 for the actor-layer idempotency rule this implies.

### `changed_files`
| column | type | notes |
|---|---|---|
| pull_request_analysis_id | bigint, null: false, FK, indexed | |
| file_path | string, null: false | unique per `pull_request_analysis_id` |
| previous_file_path | string | for renames |
| change_type | integer, null: false | enumerize: added/modified/deleted/renamed |
| additions | integer, default: 0 | |
| deletions | integer, default: 0 | |
| patch | text | raw unified diff hunk, verbatim |
| binary | boolean, default: false | |
| created_at / updated_at | | |

### `changed_code_entities`
Diff Parser structured output (§28) — bridges `changed_files` to `code_entities`.

| column | type | notes |
|---|---|---|
| pull_request_analysis_id | bigint, null: false, FK, indexed | |
| changed_file_id | bigint, null: false, FK, indexed | |
| code_entity_id | bigint, FK, indexed | nullable — PR may add a brand-new entity not in the base-branch index |
| entity_type | integer, null: false | enumerize, same set as `code_entities.entity_type` — denormalized so this row is self-sufficient when `code_entity_id` is nil |
| class_name / method_name | string | §28 "Changed Method" |
| change_kind | integer, null: false | enumerize: added/modified/removed (method/class-level, distinct from file-level `change_type`) |
| validation_changed | boolean, default: false | §28 explicitly calls out changed validations |
| association_changed | boolean, default: false | §28 explicitly calls out changed associations |
| created_at / updated_at | | |

### `graphify_artifacts`
| column | type | notes |
|---|---|---|
| pull_request_analysis_id | bigint, null: false, FK, indexed (with format) | |
| format | string, null: false | e.g. `"graph_json"`, `"graph_report_md"`, `"graph_html"` — **plain string, not enumerize**, since Graphify's real output format set is an open Phase-4 question (§9) and locking it into an enum now would risk a schema migration later |
| raw_content | text | verbatim CLI output — text, not json, since some formats are Markdown/HTML |
| parsed_content | json | normalized subset the app actually consumes (direct/indirect deps, call-graph edges) |
| graphify_version | string | CLI/tool version, for reproducibility once Phase 4 pins down the real invocation |
| generated_at | datetime | |
| created_at / updated_at | | |

### `impact_items`
Direct/Indirect Impact classification (§30–31), reworked from DependencyWeb's `ImpactAnalysisService` concept but keyed against `BusinessFeature` directly rather than a loosely-typed polymorphic target.

| column | type | notes |
|---|---|---|
| pull_request_analysis_id | bigint, null: false, FK, indexed | |
| business_feature_id | bigint, FK, indexed | nullable when evidence isn't enough to map a feature yet — pairs with `needs_manual_review` |
| code_entity_id | bigint, FK, indexed | the technical entity this impact concerns |
| source_changed_code_entity_id | bigint, FK → changed_code_entities | traceability: which PR change produced this impact — feeds the §40 collapsible "分析依據" evidence panel |
| impact_level | integer, null: false, indexed | enumerize: direct_change/direct_dependency/indirect_dependency/regression_candidate (§31) |
| reason | text | human-readable chain, e.g. "A3 冷卻 ← UpdateUsageActor ← Wms::Stock::UpdateActor" |
| evidence | json | structured evidence array (file paths / Graphify edges / diff refs) — feeds both LLM input (§34/§36) and the UI evidence panel (§40) |
| needs_manual_review | boolean, default: false | §36 "需要人工確認" |
| created_at / updated_at | | |

### `test_reports`
One PR analysis can have multiple historical reports (§63 — regenerating a report must not require redoing git/Graphify/LLM work already done).

| column | type | notes |
|---|---|---|
| pull_request_analysis_id | bigint, null: false, FK, indexed (with created_at) | |
| title / summary | string / text | |
| markdown_content | text | final rendered Markdown, matching `spec_sample.md`'s structure |
| structured_content | json, null: false | validated raw LLM JSON (§37 schema: summary/affected_modules/affected_features/test_cases/regression_cases/pass_criteria/manual_checks/uncertain_items) — kept verbatim so Markdown can be re-rendered without re-calling the LLM |
| status | integer, default: 0, null: false | enumerize: generating/completed/failed — independent of the parent PR analysis's own status (§63) |
| error_message | text | |
| generated_by | string | e.g. `"llm"` |
| llm_provider / model_name | string | §32 provider abstraction |
| prompt_version | string, null: false | §61 `TEST_SCOPE_PROMPT_VERSION` |
| input_tokens / output_tokens | integer | §62 cost tracking |
| duration_ms | integer | §62 |
| created_at / updated_at | | |

### `test_cases`
Row-per-case extraction of `test_reports.structured_content`, matching `spec_sample.md`'s per-case fields 1:1 so the UI never re-parses JSON to render/sort/filter.

| column | type | notes |
|---|---|---|
| test_report_id | bigint, null: false, FK, indexed | |
| business_feature_id | bigint, FK, indexed | cross-nav back to feature |
| impact_item_id | bigint, FK | traceability: why this case exists |
| case_type | integer, null: false | enumerize: core_change/direct_impact/indirect_impact/regression — drives §39's "建議測試順序" grouping |
| position | integer, null: false | explicit suggested order within/across groups |
| name | string, null: false | e.g. "A3 冷卻 — 下調未入包裝" |
| page_path | string | e.g. `/workstation/a3_order/:work_date` |
| verification_purpose | text | 驗證內容 |
| steps | json | ordered array of step strings — 操作步驟 |
| expected_result | text | 預期結果 |
| failure_criteria | text | 失敗判讀 |
| notes | text | 注意事項 |
| evidence | json | same evidence-linking shape as `impact_items.evidence`, feeds §40 |
| created_at / updated_at | | |

**Explicitly not added**: per-Graphify-node tables (§59 — raw/parsed JSON on `graphify_artifacts` covers it), a separate stage-audit-log table (the `status` enum + timestamps + `error_stage` on `pull_request_analyses` is sufficient for MVP).

## 5. Actor 列表

Phase-labeled per `project_plan.md` §48. **Phase 1 creates none of these** — schema/scaffold only.

- Phase 2: `Projects::Create` (fast, synchronous — validates input, finds-or-creates the `Project` row, enqueues `ProjectImportJob`) + `Projects::Import` (runs in the background job — calls the GitHub API for repository metadata, sets `default_branch`, transitions `status`/`analysis_status`, or records a human-readable failure). Split into two actors, not the single `Projects::Import` project_plan.md §48 illustrates, so the controller stays fast/synchronous (create the row, give the user immediate feedback) while the actual GitHub API call is backgrounded per §47's requirement that external calls not block the request cycle.
- Phase 7 (implemented, pulled forward from Phase 23): `Projects::Sync` — deliberately minimal: marks `status: "syncing"` and re-enqueues the same `ProjectImportJob` used for initial import (`Repositories::Clone` already handles "bare repo exists → fetch instead of re-clone", so the existing pipeline doubles as the sync pipeline with no new git logic needed). Built now because a "同步母分支" button with no working backend would be a dead UI element — full §23-specific behaviors (e.g. surfacing a distinct diff-of-what-changed-since-last-sync) are still Phase 23 scope, not built.
- Phase 3 (implemented): `Repositories::Clone`, `Repositories::Fetch`, `Repositories::CreateWorktree`, `Repositories::RemoveWorktree` — `ProjectImportJob` now runs `Projects::Import` then `Repositories::Clone` in sequence, so a project's repository is cloned automatically right after its GitHub metadata is fetched, with no separate user action. `CreateWorktree`/`RemoveWorktree` are built and tested but not yet called from anywhere — nothing needs a PR-analysis worktree until Phase 8+.
- Phase 5 (implemented): `Projects::IndexCode` — orchestrates a full base-branch scan: creates an ephemeral `"index"` worktree at `project.base_sha` (`Repositories::CreateWorktree`), runs `Graphify::Analyze` against it, classifies the resulting `graph.json` nodes into Rails entity types via `CodeEntityExtractor` (`app/services/`, not an Actor — pure data transformation, no side effects), replaces `project.code_entities` inside a transaction, then removes the worktree in an `ensure` block regardless of success/failure. Chained as the third step in `ProjectImportJob`, after `Projects::Import` and `Repositories::Clone`. See §3 for the classification approach.
- Phase 6 (implemented): `Projects::BuildBusinessModules`, `Projects::BuildBusinessFeatures` — chained as the fourth/fifth steps in `ProjectImportJob`, after `Projects::IndexCode`. See the dedicated write-up below (after §11) for the rule-based/LLM-inferred split and why it's grounded in the real target repo's actual `routes.rb`, not assumptions.
- Phase 8 (implemented): `PullRequests::PrepareAnalysis` (fast, synchronous, controller-called — mirrors `Projects::Create`: implements §51 re-run idempotency and enqueues the background job) + `PullRequests::Fetch` (background — the actual GitHub API work, mirrors `Projects::Import`). Needed no git/worktree access at all: `client.pull_request` gives title/body/author/base/head directly, and `client.compare(base_sha, head_sha)` gives `merge_base_commit.sha` directly too — §26's `git merge-base` requirement is satisfiable straight from the GitHub API, no local clone needed until Phase 9 actually computes a diff. Idempotency is keyed on `[project, pr_number]` + non-terminal status only, **not** `[project, pr_number, head_sha]` as originally sketched in §15 — head_sha isn't known until `Fetch` itself runs, so the earlier triple can't be checked at the point `PrepareAnalysis` needs to check it.
- Phase 9 (implemented): `Git::Diff`, `Git::ParseDiff`, plus `Repositories::FetchPullRequestRef` (fetches `refs/pull/<n>/head` — GitHub's well-known PR ref, never advertised by a plain fetch but always fetchable by exact path). See the dedicated write-up below (after §11) for why no worktree is needed for this phase, and how §28's structured diff parsing actually works.
- Phase 4 (implemented): `Graphify::Analyze`, `Graphify::ParseResult` — no `Graphify::Install` actor; installing `graphifyy` is a one-time host-level setup step, not a per-analysis runtime concern. See §9 for the full spike writeup (headless CLI confirmed working) and rationale.
- Phase 11: `Impacts::MapCodeEntities`, `Impacts::MapBusinessFeatures`
- Phase 12: `Llm::AnalyzeTestScope`
- Phase 13: `Reports::Build`, `Reports::RenderMarkdown`
- Phase 8 (orchestrator): `PullRequests::Analyze` — composes the full pipeline via `play`

Actor concerns anticipated (not built yet): a `Searchable`/`Sortable` pair (mirroring PrjAGWms) for `List` actors once list UIs exist (Phase 7), and a stage-tracking concern for `PullRequests::Analyze` to update `pull_request_analyses.status`/`error_stage` consistently across every step.

## 6. Controller 列表

Phase-labeled per §58. **Phase 1 creates only** `HomeController` (stub) and `Projects::BaseController` (empty placeholder).

- Phase 1: `HomeController` (stub `index` only)
- Phase 2/7 (implemented): `ProjectsController` — **top-level, not namespaced** (unlike `Projects::BaseController`): "Projects" is the root entity of this app, not a sub-feature under a bigger namespace, so it follows PrjAGWms's ungrouped-top-level-controller precedent (e.g. `SessionController`) rather than being doubly-nested as `Projects::ProjectsController`. Phase 7 added `#show` (business module/feature tree, business/technical view toggle via `?view=technical`, search via `?q=`), `#destroy` (DB record + best-effort repo-directory cleanup), `#sync` (member route, triggers `Projects::Sync`). No Blueprint yet — every response so far is server-rendered HTML, and Blueprinter is for JSON responses only; introduce one when an actual JSON endpoint exists, not speculatively.
- Phase 23: `Projects::ProjectSyncsController` (namespaced — nested under a specific project, unlike `ProjectsController` itself)
- Phase 8/25 (implemented): `Projects::PullRequestAnalysesController` — `#create` (PR number validated as integer-only per §64, calls `PullRequests::PrepareAnalysis`) + `#show` (metadata + §53 base-branch-mismatch warning; placeholder sections for 測試範圍/修改內容/Graphify/Raw Diff, Phase 9-13 not built yet)
- Phase 21: `Projects::BusinessModulesController`, `Projects::BusinessFeaturesController`
- Phase 13/41: `Projects::TestReportsController`

## 7. Blueprint 列表

Phase-labeled per §57. **None created in Phase 1.**

- `ProjectBlueprint`, `BusinessModuleBlueprint`, `BusinessFeatureBlueprint`, `CodeEntityBlueprint`, `PullRequestAnalysisBlueprint`, `TestReportBlueprint` — each introduced alongside the controller that first needs it.

## 8. Git Repository 儲存方式 — implemented in Phase 3

Per §5–6.

- `REPOSITORY_ROOT` env var (default `Rails.root.join("storage", "repositories")`), never hardcoded/scattered through the codebase. Exposed to actors via `RepositoryPaths#repository_root`, which reads `Rails.application.config.x.repository_root` first (nil by default, so it falls back to the frozen `REPOSITORY_ROOT` constant) — this mutable override point exists purely so tests can point git operations at a scratch tmpdir without ever touching real `storage/repositories`, without weakening the production default (see `test_helper.rb#with_scratch_repository_root`).
- Layout: `storage/repositories/<owner>/<repo>/repository.git` (bare) + `storage/repositories/<owner>/<repo>/worktrees/<name>/` (per-analysis isolated worktree, e.g. `worktrees/pr-65`) — implemented in `app/actors/concerns/repository_paths.rb`, shared by every `Repositories::*` actor so the `REPOSITORY_ROOT` join point exists in exactly one place.
- **`--mirror`, not plain `--bare`**: `Repositories::Clone` clones with `git clone --mirror` rather than `--bare`. A plain `--bare` clone sets up no fetch refspec to keep local branches current, so a later `git fetch origin` only updates (nonexistent, for a bare clone) remote-tracking refs, leaving `refs/heads/<branch>` permanently stale — discovered via a failing test (`Repositories::FetchTest`) during Phase 3 verification. `--mirror` configures `remote.origin.fetch = +refs/*:refs/*`, so a plain `git fetch origin` updates `refs/heads/<default_branch>` in place, matching what `Repositories::Clone`/`Repositories::Fetch` assume when resolving `base_sha` via `git rev-parse <default_branch>`.
- **Idempotent clone**: `Repositories::Clone` checks whether `repository.git` already exists; if so, it delegates to `Repositories::Fetch` instead of re-cloning (§51) — safe to call repeatedly (e.g. on retry after a failure) without erroring or duplicating work.
- Never share a single working directory across concurrent analyses (`git checkout branchA` / `git checkout branchB` on one dir) — bare repo + `git worktree add`/`remove` per PR Analysis (`Repositories::CreateWorktree`/`Repositories::RemoveWorktree`), cleaned up after completion. `RemoveWorktree` is a no-op (not an error) when the worktree directory is already gone, matching the same re-run idempotency principle.
- `projects.repository_path` stores the **relative** path only (e.g. `"AMASTek/PrjJieZhou/repository.git"`); actors join it against `REPOSITORY_ROOT` at use time via `RepositoryPaths`.
- **Credential injection**: the GitHub token is never embedded in the clone URL and never persisted into the resulting repo's `.git/config` (§3's explicit prohibition, extended to the on-disk repo config, not just the DB) — `GitCommand.auth_env` injects it via **`GIT_ASKPASS`** (`bin/git_askpass`, a small script that echoes `$GIT_ASKPASS_TOKEN` regardless of which prompt git asked for — GitHub accepts the same PAT for both username and password over HTTPS), with the token itself passed only via the `GIT_ASKPASS_TOKEN` environment variable, never a CLI argument — only readable via `/proc/<pid>/environ` by the same user or root, not visible in `ps aux`. `Repositories::Fetch` decides whether to inject auth by inspecting the bare repo's *actual* configured remote URL (only applies it for `https://github.com/...` remotes), so it stays correct regardless of who calls it, without needing a flag threaded through from the caller.
  - **Real bug found and fixed via live testing, not caught by the automated suite**: the original implementation used `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` to inject an `http.extraheader` — that env-var-based config mechanism was only added in **Git 2.31**, and this host runs **Git 2.25.1**, so it silently did nothing; git then fell back to an interactive credential prompt, which failed immediately since `GIT_TERMINAL_PROMPT=0` disables prompting ("could not read Username ... terminal prompts disabled"). Every `Repositories::*` test uses a local/public fixture repo needing no auth at all, so the auth path itself was never actually exercised until a real clone of a real *private* GitHub repo (`AMASTek/PrjJieZhou`, done as a live end-to-end validation of Phases 2/3/5 together) hit it immediately. `GIT_ASKPASS` works on any Git version, avoiding the whole class of problem. Lesson: an actor's unit tests can all pass while a code path they never exercise (auth against a real remote) is completely broken — worth a live smoke test against real credentials before considering a phase done, not just fixture-based automated tests.
- **All shell-outs go through `GitCommand`** (`app/services/git_command.rb`), which always calls `Open3.capture3` with an argument array — never a single interpolated string — so command injection (§64's explicitly named risk) is structurally not possible through this interface.
- **Security fix discovered in this phase**: `Project::OWNER_FORMAT` (`app/models/project.rb`) originally allowed values composed entirely of dots (e.g. `".."`) to pass validation, since the character class permitted `.` without requiring at least one alphanumeric character — a real path-traversal vector once Phase 3 started joining `owner`/`repository_name` directly into filesystem paths. Fixed by requiring at least one alphanumeric character in the regex. Not caught in Phase 1/2 since neither phase used these values in a filesystem path yet.

## 9. Graphify Pipeline — spike resolved in Phase 4, headless CLI confirmed working

**Previously flagged as this project's biggest open risk (Phase 1); resolved by an actual spike in Phase 4.** Result: Graphify works completely headlessly, no AI IDE required. The risk did not materialize.

### What Graphify actually is

`Graphify` (`https://github.com/Graphify-Labs/graphify`) is a **Python CLI**, PyPI package `graphifyy` (real package, `pip`-installable, requires **Python ≥3.10**), **not a Ruby gem**. It uses tree-sitter for AST-based code extraction across 40+ languages (Ruby included — `tree-sitter-ruby` is a direct dependency). Its README frames it primarily as a Claude Code/Cursor AI-IDE skill (`/graphify` slash commands), but this is a documentation/marketing framing, not a technical limitation — the underlying `graphify` binary is a genuine standalone CLI with a full `--help` listing dozens of subcommands, most of which are plain scriptable operations with no AI/chat dependency at all.

### The spike (Phase 4)

1. **Install**: this machine's system Python is 3.8 (too old for the ≥3.10 requirement), and there's no passwordless sudo to install a newer one via apt. Installed [`uv`](https://astral.sh/uv) instead (`curl -LsSf https://astral.sh/uv/install.sh | sh`, single static binary, user-space, no root needed) — `uv tool install graphifyy` then downloaded and managed its own isolated Python 3.10 build and installed `graphify`/`graphify-mcp` to `~/.local/bin`, entirely without sudo. **`uv`, not `pipx`, is the correct install path for this environment** and is recommended generally, since `uv` manages the Python version itself rather than depending on whatever `python3` happens to be on the host.
2. **Headless test**: `graphify update <path>` (run from a plain non-interactive shell, no AI IDE, `timeout 60`) against a small Ruby fixture directory (a model + a controller) completed in a few seconds, **exit code 0**, no prompts, and explicitly printed "no LLM needed" — it wrote `graphify-out/graph.json`, `graph.html`, and `GRAPH_REPORT.md`. `GRAPH_REPORT.md` confirmed "Token cost: 0 input · 0 output" for the extraction itself (LLM calls are opt-in, only for community *naming*/semantic doc extraction via `graphify cluster-only`/`graphify label`, never required for the base graph).
3. **Output quality**: `graph.json` contains real structured nodes (classes, methods, files) and typed edges (`calls`, `contains`, `inherits`, etc.) with `source_file`/`source_location` and a `confidence`/`confidence_score` per edge — directly useful for §28 (Diff Parser structured output) and §36 (LLM input must carry traceable evidence, not invented claims). `graphify affected "<Node>"` performs exactly the reverse-dependency traversal project_plan.md §29-31 needs ("who depends on the thing that changed"), and `graphify query "<question>"` supports ad-hoc BFS exploration — both are headless, scriptable, and operate on the already-built `graph.json` with no LLM call.
4. **PATH gotcha (real, not session-specific)**: `uv tool install` places binaries under `~/.local/bin`, which its installer wires into `.bashrc`/`.profile` — but those are only sourced by *interactive* shells, not guaranteed for however a production app server or Solid Queue worker process gets launched (systemd, Docker entrypoint, etc.). Fixed via `config/initializers/graphify_definition.rb`, which prepends `~/.local/bin` to `ENV["PATH"]` at boot if not already present — so `GraphifyCli` (and the app generally) doesn't depend on the parent process's shell setup. This must also be reflected in `docs/setup.md` (not yet written, per §77) as an explicit deployment step: `uv tool install graphifyy` on any host that runs the app or its background workers.

### Implementation (Phase 4)

- `GraphifyCli` (`app/services/graphify_cli.rb`) — thin `Open3.capture3`-based wrapper, mirroring `GitCommand`'s shape: array-args only (no shell interpolation), raises `GraphifyCli::NotInstalled` specifically on `Errno::ENOENT` (missing binary) vs a generic `GraphifyCli::Error` for any other non-zero exit, so callers can produce the right §67 error message ("Graphify 安裝失敗" vs "Graphify 執行失敗").
- `Graphify::Analyze` — input `path:`, output `output_dir:`. Deliberately **not** coupled to `PullRequestAnalysis` — it just runs `graphify update <path>` and reports where the output landed. Kept generic (rather than assuming PR-analysis status semantics) so it stays reusable wherever a code graph is needed, not just the PR pipeline.
- `Graphify::ParseResult` — input `pull_request_analysis:`, `output_dir:`; output `graphify_artifacts:`. This is the layer that knows about the DB: reads `graph.json` (stored as both `raw_content` and parsed `parsed_content`) and `GRAPH_REPORT.md` (raw text only) from `output_dir`, persists them as `GraphifyArtifact` rows, tags each with `GraphifyCli.version`. `graph.html` is intentionally **not** persisted to the DB — it's a multi-MB self-contained visualization better regenerated on demand than stored as a TEXT blob (consistent with §4's JSON-vs-TEXT sizing rationale).
- **No `Graphify::Install` actor** (project_plan.md §48's illustrative list includes one) — deliberately not built. Installing `graphifyy` is a one-time **host-level** setup concern (same category as `bundle install`, `git`, or MySQL client libraries), not a per-analysis runtime step; running `uv tool install` inside a live background job would be wasteful and architecturally odd. This is exactly the kind of illustrative-name-not-literally-required case §48 itself anticipates ("不要為了套 Pattern 而建立大量只有一兩行的 Actor"). Instead, `GraphifyCli::NotInstalled` gives a clear, actionable §67-style error if the one-time host setup was skipped.
- **Not yet wired into a live pipeline** — like Phase 3's `CreateWorktree`/`RemoveWorktree`, these actors are built and tested against real fixtures but not yet called from anywhere; nothing creates a `PullRequestAnalysis`-driving worktree until Phase 8+ (PR Analysis Pipeline). Verified via `Graphify::AnalyzeTest`/`Graphify::ParseResultTest`, which run the *real* `graphify` binary against a real tiny fixture directory (no mocking of Graphify's own behavior) — consistent with how Phase 3 tested real git operations rather than just stubbing `GitCommand`.

### Real end-to-end validation, not just fixtures

After Phase 5, the whole `ProjectImportJob` pipeline (Import → Clone → IndexCode) was run live against `AMASTek/PrjJieZhou` — the actual target repository the spec's own examples reference, not a fixture. This required a real `GITHUB_ACCESS_TOKEN` (reused from `/home/micky/DependencyWeb`'s Rails credentials with the user's explicit go-ahead, stored in a git-ignored `.env` loaded by `dotenv-rails` in development/test only — see Gemfile) and surfaced a real bug the fixture-based test suite structurally couldn't catch: fixtures are always local/public and never exercise the GitHub auth path at all, so `GitCommand.auth_env`'s Git-2.31-only mechanism silently failing on this host's Git 2.25.1 (§8) went undetected until a real private-repo clone hit it immediately. Once fixed (`GIT_ASKPASS`), the full pipeline succeeded: cloned a real ~11MB private Rails repo, scanned and classified **1,219 code entities** (720 actors, 198 controllers, 97 models, 71 views, 57 routes, 49 concerns, 25 blueprints, 1 job, 1 mailer), and correctly cleaned up its scan worktree afterward. Notably, the real `config/routes.rb` already carries Traditional-Chinese comments per route (e.g. `post "work_orders/create" => "work_orders#create" # 新增工單`) — directly confirming the premise behind §15's "prefer existing Chinese labels over LLM-invented ones" is actionable against this actual codebase, not just a hopeful assumption. **Takeaway for future phases**: prefer a live smoke test against real credentials/data over trusting fixture-based automated tests alone before considering a phase done — see §8's askpass bug writeup for exactly what that caught.

## 10. PR Analysis Pipeline

Per §25, `pull_request_analyses.status` advances through the stages below (values map 1:1 to spec §46's list, plus `llm_failed` — see §4's schema section). **Implemented so far, in `PullRequestAnalysisJob`** (Phase 8-9): `queued → fetching_pr → diffing`. Not yet built: everything from `graphifying` on.

```
queued
  → fetching_pr           (PullRequests::Fetch — GitHub PR metadata + merge-base via octokit)   [Phase 8]
  → diffing                (Git::Diff — merge-base-aware diff, Git::ParseDiff for §28 structured output)   [Phase 9]
  → graphifying             (Graphify::Analyze / Graphify::ParseResult — needs a real worktree, see below)   [Phase 10, not built]
  → mapping_features        (Impacts::MapCodeEntities, Impacts::MapBusinessFeatures)   [Phase 11, not built]
  → llm_analyzing           (Llm::AnalyzeTestScope)   [Phase 12, not built]
  → building_report         (Reports::Build, Reports::RenderMarkdown)   [Phase 13, not built]
  → completed
(any stage) → failed / llm_failed
```

**No `creating_workspace` stage is actually used by Phases 8-9** — deviates from the original Phase 1 sketch, which assumed a worktree gets created early (right after fetching PR metadata) and everything downstream uses it. In practice, `git diff` operates directly on the bare repo's object database once the PR's head commit is fetched (`Repositories::FetchPullRequestRef` — no worktree needed for that at all), and `Git::Diff`'s own status transition goes straight from `fetching_pr` to `diffing`. `creating_workspace` (and an actual `Repositories::CreateWorktree` call, named `pr-<n>`) is deferred until Phase 10, which is the first stage that genuinely needs real files on disk (Graphify has no notion of git objects, only a filesystem path).

**No `PullRequests::Analyze` orchestrator exists yet** — `PullRequestAnalysisJob` chains actors directly (`PullRequests::Fetch` → `Git::Diff` → `Git::ParseDiff`, growing by one call per phase as each is built), mirroring exactly how `ProjectImportJob` grew incrementally through Phases 2-7 rather than being written as one `play`-based actor upfront. A dedicated orchestrating Actor may still be introduced later if the job body gets unwieldy, but isn't needed yet at three steps.

The user never manually triggers individual stages (§25) — clicking "分析 PR" enqueues one Solid Queue job.

### Phase 9 implementation notes

- **No worktree needed for the diff itself** (see above) — only `Repositories::FetchPullRequestRef` runs, fetching GitHub's well-known `refs/pull/<n>/head` ref (confirmed against the real target repo: never advertised by a plain `git fetch`/`ls-remote`, but always fetchable by exact ref path — a documented GitHub convention, not a guess).
- **`merge_base_sha`, not `base_sha`, is the actual diff comparison point** (§26) — `Git::Diff#base_ref` uses `merge_base_sha` (resolved in Phase 8 via GitHub's compare API) with a fallback to `base_sha` only if that resolution failed. Using plain `base_sha` would compare against wherever the base branch happens to sit *now*, not where the PR actually branched from — exactly the "不要單純相信目前 checkout branch" mistake §26 warns against, just via a stale `base_sha` instead of a stale checkout.
- **`GitDiffParser`** (`app/services/`) parses `git diff --name-status -M -z` (NUL-separated, so a rename's old/new paths are genuinely separate fields — deliberately *not* `--numstat`'s rename output, which encodes `old => new` ambiguously in one field) for the file list/status, and computes each file's additions/deletions by counting `+`/`-` lines directly in its own patch text rather than trusting a separate numstat call — one less place for the two sources to disagree.
- **`RubyDiffHunkScanner`** (§28's actual "Diff Parser") determines each hunk's enclosing class/method from **two sources in order**, letting the second override the first: (1) git's own hunk-header trailer (`@@ ... @@ class Foo`/`def bar`) — the only source when the enclosing definition is too far away to appear in the diff's 3-line context window at all; (2) the hunk body itself. Source (2) matters because source (1) alone can point at the *wrong* method — confirmed with a real constructed example: a hunk starting right at a blank line just before `def show` fell back to header text `def index` (an earlier, unrelated method), while `def show` still reliably appeared as unchanged context *within* the hunk body, which scanning the body and letting it override the header correctly catches. Validated against a real PR diff from the target repo too (correctly extracted `WorkOrder::EstimatedCompletion#other_producing_orders_for_total_speed` from a real multi-line hunk that also renamed the method).
- **Entity classification reuses Phase 5's `CodeEntityExtractor::TYPE_BY_PATH_PREFIX`** directly rather than duplicating the Rails-directory-convention table — a changed file is classified the same way whether it's being scanned for the base index or for a PR diff.
- **Linking to the base index**: each extracted `ChangedCodeEntity` looks up a matching `CodeEntity` by `[entity_type, class_name, method_name]`; found → `code_entity_id` set (this is an existing entity being changed); not found → left `nil` (a brand-new method/class the PR itself introduces, not yet in the base index — correctly distinct from "changed", matching §28's implied need to tell these apart). Verified against the real PR diff: correctly linked back to the base-index `CodeEntity` for the actor method it modified.
- Files outside the Rails directory conventions `CodeEntityExtractor` recognizes (e.g. `spec/**`) are still recorded as `ChangedFile` rows (full patch, stats) but produce no `ChangedCodeEntity` — verified against the real PR, which also touched a spec file alongside the actor file.

## 11. LLM Analysis Pipeline

Per §32–37, plus a specific user request for the provider abstraction to be genuinely modular across all three major vendors (not just Gemini), switchable by env var + paid key alone.

### Implementation (pulled forward from Phase 12, into Phase 6)

Built earlier than originally planned because Phase 6's business-feature naming (see below) is the first real consumer — a custom, non-CRUD controller action (`cooling`, `scrap`, `approve`, …) needs an actual LLM call to name, not a lookup table.

- `Llm::Provider` (`app/services/llm/provider.rb`) — abstract interface with one method, `generate(prompt:, system: nil, json: false)`, returning a uniform `Llm::Response` (`content`, `input_tokens`, `output_tokens`, `provider`, `model`) regardless of which vendor answered. `Llm::Provider.current` is a factory reading `LlmConfig.provider` (`LLM_PROVIDER` env var: `openai` | `claude` | `gemini`, default `gemini`) — **switching providers is a one-line env var change plus the matching API key env var, never a caller code change.**
- Three real implementations, all built (not just Gemini): `Llm::OpenAiProvider` (Chat Completions API), `Llm::ClaudeProvider` (Anthropic Messages API), `Llm::GeminiProvider` (`generateContent`). All three go through `Faraday` directly (added as an explicit Gemfile dependency, not relying on octokit's transitive one) — no per-vendor SDK gems, so the three implementations share one HTTP-client mental model instead of three different gems' quirks.
- **Structured output, made consistent across vendors deliberately**: rather than using each vendor's own (differently-shaped) native structured-output API — OpenAI's `response_format`, Gemini's `responseSchema`, Claude's forced tool-use — every provider gets the *same* plain-text instruction appended to the prompt when `json: true` ("Respond with valid JSON only..."), and `Llm::Response#parsed_json` strips stray ` ```json ` fences before parsing. This is the direct answer to "keep the analysis process and report format stable regardless of which provider is plugged in": the prompt-construction and response-parsing code is 100% shared across all three vendors — only the HTTP request/response shape differs, isolated inside each provider class.
- `LlmConfig` (`config/initializers/llm_definition.rb`): `DEFAULT_MODELS`/`API_KEY_ENV_VARS` hashes keyed by provider name (`gpt-4.1`/`OPENAI_API_KEY`, `claude-sonnet-4-5`/`ANTHROPIC_API_KEY`, `gemini-2.5-flash`/`GEMINI_API_KEY`), with `LLM_MODEL` as a global override for any provider's default. All lazy (`ENV.fetch` only evaluated when an Actor actually calls `LlmConfig.api_key`), matching the established pattern.
- Tests stub Faraday's own built-in test adapter (`Faraday::Adapter::Test::Stubs`) with realistically-shaped canned responses per vendor — no real API calls, no per-vendor mocking gem needed, consistent with never hitting paid/external APIs from the automated suite (§68).
- Input assembly (§34: project info, PR metadata, changed files/classes/methods, relevant diff hunks, Graphify dependencies, mapped business modules/features, routes, relevant models/actors/views/i18n text — never the whole repository) and the §37 structured-JSON test-scope schema are Phase 12 work, not yet built — only the provider abstraction itself exists so far.
- `TEST_SCOPE_PROMPT_VERSION` (env-configurable, default `"v1"`) is recorded on every `test_reports` row (§61) so prompt changes are auditable against historical reports.
- Cost tracking: `input_tokens`/`output_tokens`/`duration_ms`/`llm_provider`/`model_name` recorded per report (§62) — `Llm::Response` already carries the first three of these uniformly from any provider.
- Every test case must carry `evidence` tracing back to real source (§36) — file paths, Graphify edges, diff refs; when evidence is insufficient, the case is marked "需要人工確認" rather than invented.

### Phase 6: Business Module / Feature construction — the rule-vs-LLM split, and why

Raised explicitly by the user before this phase was built: don't repeat DependencyWeb's `DEFAULT_OPERATION_PLAYBOOK` mistake — a hardcoded Ruby Hash that generated the *entire* report deterministically, with no real reasoning anywhere in the pipeline. The division of labor here is deliberate:

1. **Deterministic (no LLM, no guessing)** — `RoutesFileParser` (`app/services/routes_file_parser.rb`) parses `config/routes.rb` into resolved `{controller:, action:, comment:}` entries, correctly qualifying controller names through nested `namespace`/`scope module:` blocks (a flat line-scan — what Phase 5's `CodeEntityExtractor` does for its raw catalog — gets this wrong for anything namespaced; confirmed against the real target repo, where most controllers live inside `namespace :setting do...end` etc). `Projects::BuildBusinessModules` groups routes by controller and creates one `BusinessModule` per controller; `Projects::BuildBusinessFeatures` + `BusinessFeatureNamer` (`app/services/`) decide each feature's name in strict priority order:
   - **A route-line comment always wins** (§15's "prefer existing Chinese labels" — literally the developers' own label). Confirmed empirically, not assumed: the real target repo's actual `routes.rb` already carries comments like `post "work_orders/create" => "work_orders#create" # 新增工單` and, on `resources` lines, a comment naming the *whole resource* (`resources :customers, except: [:destroy] # 客戶管理`) — captured separately as `resource_comments` and used for the `BusinessModule` name itself (with a trailing `管理` stripped, e.g. "客戶管理" → "客戶" — confirmed against all 14 real resource comments, 12 of which end in 管理 and 2 which don't and are left as-is).
   - **Standard CRUD action names** (`index`/`show`/`new`+`create`/`edit`+`update`/`destroy`) use the §14 rule table (`BusinessFeatureNamer::CRUD_GROUPS`) — `new`/`create` collapse into one "新增X" feature and `edit`/`update` into one "編輯X" feature (an operator sees one "新增使用者" feature, not two, matching the spec's own worked example).
2. **LLM-inferred (real reasoning, only when rules can't decide)** — an action with *neither* a comment *nor* a standard CRUD name (e.g. a custom `cooling`/`scrap`-style action) calls `Llm::Provider.current.generate(...)` with the controller/action/resource as evidence, asking for a short Traditional-Chinese feature name grounded in that evidence — never a lookup table. On the real target repo, **zero** actions needed this path — every custom action already had a route comment — but the path exists, is tested (stubbed LLM response), and fails *gracefully* per-action (skips that one feature, logs, continues) rather than crashing the whole scan if the LLM call itself errors (e.g. no API key configured), consistent with §63's "one stage's failure shouldn't destroy other completed work."

**Real end-to-end validation** (not just fixtures): run against the actual cloned `AMASTek/PrjJieZhou` (project id 6 in this environment) — **19 business modules, 93 business features, 107 feature↔code-entity links**, 35 `locale_derived` + 58 `route_derived` + 0 `llm_inferred` (confirming the rule-based path alone handles this real repo completely). Output quality spot-checked directly: "客戶" module → "客戶列表"/"新增客戶"/"編輯客戶"/"客戶詳細資料"; "工單" module → "工單列表"/"新增工單"/"開始加工"/"停止加工"/... — matching the spec's own naming style. One real bug this surfaced and fixed: three separate `*BaseController` routes (`Setting::BaseController`, `Estimate::BaseController`, `Pms::BaseController` — plain redirect routes with no `resources` comment to derive a name from) all humanized to the identical "Base", indistinguishable in the module list; `BuildBusinessModules#humanize_controller`'s English fallback now includes the namespace ("Setting Base", "Estimate Base", "Pms Base").

**Known limitation, not yet addressed**: `*BaseController` redirect routes still generate a module/feature each, even though they're navigation plumbing, not a real business concept — left as-is for now rather than special-casing "controllers that only redirect" and risking over-fitting the design to this one target repo's specific convention.

## 12. Test Report Pipeline

`spec_sample.md` (in this repo) is the confirmed concrete target format, matching §39's structure exactly: 修改摘要 table → 操作頁面↔驗證目的對照總表 → 測試前準備 → 各模組測試步驟 (per case: 頁面/驗證內容/操作步驟/預期結果/失敗判讀/注意事項) → 測試通過標準 → 建議測試順序 → 附錄：操作人員回報資訊.

Mapping to schema (§4): `test_reports.markdown_content` holds the fully rendered document; `test_reports.structured_content` holds the raw validated LLM JSON it was rendered from; `test_cases` rows (one per case) carry `page_path`/`verification_purpose`/`steps`/`expected_result`/`failure_criteria`/`notes`/`evidence` — a 1:1 field match to the per-case table in `spec_sample.md`, so the UI (Phase 14) can render/sort/filter cases directly from `test_cases` without re-parsing `structured_content`. `test_cases.case_type` (core_change/direct_impact/indirect_impact/regression) plus `position` drive the "建議測試順序" ordering (§39, §31).

## 13. 頁面與 Route 規劃

- `/` — homepage: GitHub import form + imported-project cards (§18–19). **Implemented (Phase 2/7)**: each card links to its detail page, shows status/default_branch/last_synced_at, and has working 同步/刪除 actions (not decorative — `同步` calls `Projects::Sync`, `刪除` calls `ProjectsController#destroy` behind a Turbo confirm dialog per §19's "must have Confirmation").
- `/projects/:id` — Project Detail Page. **Implemented (Phase 7)**: 專案資訊, 母分支同步 button, Business Module/Feature tree (business view default, `?view=technical` toggle per §22, `?q=` search per §56 filtering both the feature tree and a matched-code-entities list). **Not yet implemented**: PR 分析 input and 歷史 PR 分析 (§20, §24-25) — shown as explicit "尚未支援" placeholders rather than silently omitted, so the page layout matches §20's required sections even though the PR pipeline itself is Phase 8+ work.
- `/projects/:id/pull_request_analyses/:id` — Analysis Detail Page, tabs: 測試範圍 (default, §42) / 修改內容 / 業務視圖 / 技術視圖 / Graphify / Raw Diff (§41, §45). Not yet built (Phase 8+).
- Route namespacing mirrors controller namespacing where a real sub-resource exists — `resources :projects do member { post :sync } end` today; `namespace :projects do resources :business_modules, :business_features, :pull_request_analyses end` (PrjAGWms's `namespace` + `resources` + `collection`/`member` pattern) is the plan for when those get their own controllers in a later phase, per §6's `Projects::BaseController` note.

## 14. Background Job 規劃

- **Solid Queue** — DB-backed, no Redis — a deliberate deviation from PrjAGWms's default in-process `async` adapter, justified by this project's much heavier background workloads.
- **Two-database split (revised from the original Phase 1 single-database plan)**: `config/database.yml` defines a `primary` connection (MySQL, the shared server per §4) and a separate `queue` connection (**local SQLite**, `config.solid_queue.connects_to = { database: { writing: :queue } }`), with Solid Queue's own migrations living in `db/queue_migrate/` instead of `db/migrate/`. This split exists because Solid Queue's dispatcher issues `SELECT ... FOR UPDATE SKIP LOCKED` queries to claim jobs safely under concurrency, and `SKIP LOCKED` requires **MySQL 8.0.1+** — the shared server this project's primary data lives on is **MySQL 5.7.42**, which raises a SQL syntax error on that query and crash-loops the dispatcher process. Discovered empirically during Phase 2 verification (the dispatcher kept restarting via Solid Queue's supervisor). Local SQLite has no such requirement and needs no additional credentials/infrastructure, preserving the original "no Redis, minimal new infra" rationale for choosing Solid Queue in the first place. All application domain tables (§4) stay exclusively on the MySQL `primary` connection — only Solid Queue's own internal tables use `queue`.
- Phase 1/2: install Solid Queue, single `default` worker pool, `config.active_job.queue_adapter = :solid_queue` (non-test envs), `:inline` in `test.rb` — note `ActionDispatch::IntegrationTest` subclasses (controller/request tests) get `ActiveJob::TestHelper` auto-included by `ActiveJob::Railtie`, which forces the `:test` adapter for *those specific test classes* regardless of the `:inline` environment setting; such tests must wrap job-triggering calls in `perform_enqueued_jobs { ... }` to actually execute the job synchronously rather than merely capture it.
- Operations that MUST be backgrounded once they exist (§47): GitHub project import/sync (git clone/fetch), Graphify execution, LLM calls, and the full PR analysis orchestration. Per-pipeline-stage dedicated queues (e.g. separate `github`/`graphify`/`llm` queues with different concurrency) are a Phase 8+ optimization, not designed now.

## 15. Error Handling

Per §67, human-readable error catalogue (never raw "Internal Server Error"):
- GitHub Repository 找不到 (404 from octokit)
- GitHub Token 權限不足 (401/403 from octokit)
- PR #N 不存在
- Graphify 安裝失敗
- Graphify 執行失敗
- LLM API 回應失敗
- LLM 回傳格式錯誤 (schema validation failure)

Technical detail goes to structured logs with a `[PRAnalysis:<id>]` correlation prefix (§66); user-facing messages stay in `pull_request_analyses.error_message`/`test_reports.error_message`.

**Retry/resume design**: `pull_request_analyses.error_stage` records which pipeline stage failed, so a retry can resume from that stage rather than re-running the whole pipeline (§51) — critical for LLM failures specifically (§63): an `llm_failed` status means git/worktree/diff/Graphify/impact-mapping work already done is preserved, and "重新產生測試報告" only re-runs `llm_analyzing` → `building_report`.

**Re-run idempotency** (§51, implemented in Phase 8): since `[project_id, pr_number]` is intentionally non-unique in the schema (history must be kept, §19/§52), idempotency is enforced at the Actor layer, not the DB layer — `PullRequests::PrepareAnalysis` looks up an existing **non-terminal** (`status` not in `PullRequestAnalysis::TERMINAL_STATUSES` = `completed`/`failed`/`llm_failed`) row for the same `[project_id, pr_number]` and reuses it instead of inserting a duplicate. Keyed on `[project_id, pr_number]` only, not `[project_id, pr_number, head_sha]` as originally sketched here — `head_sha` isn't known until `PullRequests::Fetch` (the next actor in the chain) actually calls GitHub, so it can't be part of the lookup key the *earlier* actor uses.

**Snapshot integrity** (§52): every `PullRequestAnalysis` row freezes its own `base_sha`/`head_sha`/`merge_base_sha` at creation time — a later `projects.base_sha` sync must never retroactively change what a historical report was analyzed against.

**Base/PR branch mismatch** (§53): if a PR's actual `base_branch` (from GitHub) differs from the project's current `default_branch`, the UI must show a warning and the analysis must use the PR's real base SHA — never silently substitute the project's default branch.

## 16. Security

Per §64–66:
- No shell command ever interpolates user input directly (`system("git clone #{input}")` is forbidden). All shell-outs use `Open3.capture3` (or equivalent) with argument arrays, never string interpolation into a shell command line.
- `owner`/`repository_name` validated against `\A[A-Za-z0-9_.\-]+\z` at the model level before any use in a path or API call.
- PR number: integer-only, coerced/validated before use.
- `repository_path` (relative, under `REPOSITORY_ROOT`) is validated against path traversal (`../`) before every filesystem join.
- Users never input raw ssh/shell commands or arbitrary GitHub URLs — only `owner`/`repository_name`, and the system composes the GitHub API request itself (§65).
- `GITHUB_ACCESS_TOKEN`, `GEMINI_API_KEY` (and future LLM provider keys): sourced only via `ENV.fetch` behind lazy accessor modules (`GithubConfig.access_token`, `LlmConfig.api_key`) — never hardcoded, never persisted to the DB, never logged, never included in an exception message, never rendered to a view. The full authenticated clone URL (which embeds the token) is likewise never persisted — only the relative `repository_path` is stored; the token is injected at clone/fetch time only, from the env accessor, never from a stored value.
- Logs use a `[PRAnalysis:<id>]` correlation prefix (§66) for traceability without ever logging secrets or full source content.
