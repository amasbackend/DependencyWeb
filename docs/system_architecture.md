# System Architecture

What this system is, how its pieces fit together, and where to look for more. For phase-by-phase design rationale, real bugs found during development, and real-data validation notes, see `docs/architecture_plan.md` — this document is the condensed, reader-facing summary; that one is the working history.

## What this is

A GitHub PR test-scope analyzer, purpose-built for Rails codebases. Given a repository and a PR number, it produces a **test scope report written for the person who has to click through the app and verify it still works** — which pages to open, what to do, what to expect, what counts as a failure — not a code review and not a dependency graph dump.

The core belief the whole design follows: a deterministic pipeline (git, Graphify, the impact graph) should decide *what* changed and *what depends on it*, with full traceable evidence at every step; an LLM should only be used for the one thing it's actually good at — translating that evidence into operator language — and only where the deterministic pipeline genuinely can't resolve something with confidence. When evidence is insufficient, the system says so explicitly ("需要人工確認") rather than guessing.

## Architecture

Follows `/home/micky/PrjAGWms`'s conventions: the Actor pattern (`service_actor` gem) for all business logic, thin namespaced controllers that call exactly one Actor, Blueprinter for JSON (not yet needed — no JSON API endpoints exist), `enumerize` + a central `ModelEnum` registry for all enums, zh-TW i18n split by concern (`actor`/`controller`/`model`/`enum` YAML files). See `docs/architecture_plan.md` §1 for the full mapping and the deliberate deviations (MySQL instead of SQL Server, `ENV`-based GitHub/LLM secrets instead of Rails credentials, no auth layer).

Three domain layers, kept strictly separate (`project_plan.md` §74):

```
Layer 1 — Code            CodeEntity (model/controller/actor/route/view/...)      "what changed?"
Layer 2 — Business Feature BusinessModule → BusinessFeature                        "what feature was touched?"
Layer 3 — Operator Test    TestReport → TestCase                                   "what does an operator test?"
```

## Database

MySQL 8.0+ recommended (mysql2 adapter, utf8mb4) for `primary` — the version actually running in this environment is MySQL 5.7, which works but lacks `SKIP LOCKED`, hence the separate `queue` database below. 12 domain tables:

```
Project ──< BusinessModule ──< BusinessFeature >──< FeatureCodeEntity >── CodeEntity
Project ──< CodeEntity
Project ──< PullRequestAnalysis ──< ChangedFile ──< ChangedCodeEntity
                                 ──< GraphifyArtifact
                                 ──< ImpactItem  (→ BusinessFeature, CodeEntity, ChangedCodeEntity)
                                 ──< TestReport ──< TestCase  (→ BusinessFeature, ImpactItem)
```

`json` columns hold structured payloads the app reads as Ruby objects (parsed `graph.json`, LLM structured output, evidence arrays); `text`/`longtext` columns hold verbatim blobs (raw diffs, raw Graphify CLI output, rendered Markdown) — three of these needed `LONGTEXT` specifically because MySQL's default `TEXT` caps at 65,535 bytes and real Graphify output on a 1,200+ entity codebase blew past that during live validation. Full column-by-column schema: `docs/architecture_plan.md` §4.

## GitHub Pipeline

`Projects::Create` (idempotent — returns the existing project if already imported) enqueues `ProjectImportJob`, which chains: `Projects::Import` (fetch metadata + default branch via `octokit`) → `Repositories::Clone` (real `git clone --mirror`, not the GitHub Contents API) → `Projects::IndexCode` (base code index) → `Projects::BuildBusinessModules`/`BuildBusinessFeatures` (business mapping). All through `octokit`, never raw `Net::HTTP` — this codebase's predecessor (`/home/micky/DependencyWeb`) did that and had no rate-limiting, auth centralization, or retry handling as a result.

The GitHub *default branch* is auto-detected by default (`Projects::Import`); a manual override exists as a collapsed "Advanced Option" on the import form (`Projects::Create#default_branch`) for the rare repo where the reported default isn't the one to analyze — never a required field.

## Repository Storage

```
storage/repositories/<owner>/<repo>/repository.git       — bare mirror clone (shared, long-lived)
storage/repositories/<owner>/<repo>/worktrees/<name>/     — ephemeral, one per operation
```

`git clone --mirror` (not `--bare`) specifically so a later `git fetch` updates local refs in place — a plain `--bare` clone configures no refspec to do that. Every operation that needs real files on disk (Graphify; nothing else does) creates a named worktree, uses it, and removes it in an `ensure` block — worktrees never survive past the actor that created them, success or failure. Auth for private-repo clones goes through `GIT_ASKPASS` (a tiny script echoing a token from an env var), not `GIT_CONFIG_*` env vars — the latter only works on Git ≥2.31 and silently no-ops on older versions, which cost real debugging time to discover.

GitHub PR refs (`refs/pull/<n>/head`) are fetched explicitly by exact ref path — GitHub honors this even though it's never advertised by a plain `git fetch`/`ls-remote`.

## Graphify Pipeline

[Graphify](https://github.com/Graphify-Labs/graphify) is a real, headless-capable Python CLI (package `graphifyy`, tree-sitter based) — not an AI-IDE-only tool, despite how its own README frames it. `graphify update <path>` produces `graph.json` (a NetworkX-style node-link graph: `nodes`/`links`, each link carrying `relation` — `calls`/`inherits`/`mixes_in`/`extends` are genuine dependency edges; `method`/`contains` are structural AST-encoding edges, not dependencies, and must be filtered out or every changed method falsely appears "depended on" by its own enclosing class) with zero LLM calls for the base extraction.

Two call sites, both worktree-scoped and always cleaned up:
- **Base index** (`Projects::IndexCode`, at the project's default branch) — `CodeEntityExtractor` classifies each graph node into a Rails `entity_type` by directory convention (Graphify itself has no notion of Rails conventions), plus a shallow `routes.rb` scan and an `app/views/**` file scan for the two entity kinds Graphify can't see at all.
- **Per-PR** (`Graphify::AnalyzePullRequest`, at the PR's head commit) — same tool, same output shape, feeds the impact analysis below.

Graphify's own AST-encoding output is never shown to an operator as-is (`project_plan.md` §72.6 explicitly forbids this) — it's always one input into the impact/business-feature translation, never the report itself.

## Business Feature Mapping

`BusinessFeatureNamer` decides each feature's Traditional-Chinese name in strict priority order — deterministic first, LLM only as a last resort:

1. **A `routes.rb` comment wins**, if the developers already wrote one (`resources :customers # 客戶管理`) — literally reusing an existing human label beats generating anything.
2. **Standard CRUD action names** (`index`/`show`/`new`+`create`/`edit`+`update`/`destroy`) map through a fixed rule table (`new`+`create` collapse into one "新增X" feature, matching how an operator actually thinks about it, not how routes.rb happens to be split).
3. **Only a genuinely custom, uncommented action** (e.g. `cooling`, `scrap`) calls the LLM, grounded in the controller/action/resource as evidence — never a hardcoded lookup table (the specific mistake this project's predecessor made). A per-action LLM failure is logged and skipped, not fatal to the whole scan.

`FeatureCodeEntity` currently only links **controller-action** code entities to features directly — an actor/model-level PR impact resolves to a feature only if the reverse-dependency graph walk (below) happens to reach a linked controller action within its hop cap; otherwise it's correctly flagged `needs_manual_review` rather than guessed.

## PR Analysis Pipeline

One background job, `PullRequestAnalysisJob`, chains everything after a user clicks "分析 PR" — no manual "download branch / run Graphify / call the LLM" steps ever exist in the UI:

```
queued
  → fetching_pr      PullRequests::Fetch          GitHub PR metadata + merge-base, via octokit only
  → diffing          Git::Diff, Git::ParseDiff     merge-base-aware diff; structured per-class/method output
  → graphifying       Graphify::AnalyzePullRequest  real worktree at head_sha → graph.json
  → mapping_features  Impacts::MapCodeEntities,     reverse-dependency graph walk → direct/indirect/regression
                       Impacts::MapBusinessFeatures  classification → resolved BusinessFeature (or needs_manual_review)
  → llm_analyzing     Llm::AnalyzeTestScope         evidence → operator-facing structured JSON
  → building_report   Reports::Build,               view-model assembly → rendered Markdown
                       Reports::RenderMarkdown
  → completed
(any stage) → failed / llm_failed
```

`llm_failed` is a distinct terminal state from `failed` specifically so an LLM-layer failure (bad API key, malformed response, timeout) never discards the git/Graphify/impact work that already succeeded — "regenerate report" only needs to re-run from `llm_analyzing`, not the whole pipeline.

**Impact classification** (`GraphifyGraphIndex` + `Impacts::MapCodeEntities`) reverse-walks the PR's own graph from each changed entity, capped at 5 hops: `direct_change` (the entity itself) → `direct_dependency` (1 hop) → `indirect_dependency` (2+ hops) → `regression_candidate` (other consumers of the same model class the change transitively touches, but not on its call chain — the reused "model_consumer" concept). Every classification carries the real edge chain as evidence, not just a label.

## LLM Pipeline

`Llm::Provider.current` is a factory over three real vendor implementations (`OpenAiProvider`/`ClaudeProvider`/`GeminiProvider`, all via `Faraday` directly), selected by `LLM_PROVIDER` + the matching API key — switching vendors is a config change, never a caller code change. All three return a uniform `Llm::Response`; structured-output handling is identical across vendors (a shared "respond with JSON only" instruction + fence-stripping), not each vendor's differently-shaped native structured-output API.

`Llm::TestScopeInputBuilder` assembles the *only* thing the LLM ever sees: project/PR metadata, changed files (patch excerpts, not full patches), changed classes/methods, and — the centerpiece — the already-computed impact items, each tagged with a short reference token (`IMPACT-3`) the LLM must cite to ground any test case in real evidence. The full repository is never sent (`project_plan.md` §34/§62's explicit cost/hallucination-control rule).

`Llm::TestScopeSchema` validates the response's structure before anything is trusted enough to persist — every test case must cite a real `impact_item_refs` token and carry non-empty `evidence`; a `feature` must come from the exact list of this project's real `BusinessFeature` names, never an invented one; genuinely uncertain items go into a separate `uncertain_items` array rather than becoming a forced-but-ungrounded test case. A validation failure is `llm_failed`, same as any other LLM-layer error — never a partial or best-effort save.

## Test Report Pipeline

`Reports::Build` (pure computation) + `Reports::RenderMarkdown` (pure templating) turn the validated LLM output plus its `TestCase` rows into the exact document shape confirmed against `spec_sample.md`: 修改摘要 → 操作頁面↔驗證目的對照總表 → 測試前準備 → 各模組測試步驟 (page/purpose/steps/expected result/failure criteria/notes per case) → 測試通過標準 → 建議測試順序 (ordered by the same direct→indirect→regression priority the impact classification already established) → 需要人工確認 (omitted entirely when empty, never shown as a hollow section) → 附錄. Saved as both `structured_content` (the validated JSON, for programmatic use) and `markdown_content` (the rendered document, viewable in the UI or downloadable as a `.md` file).

## Background Job

**Solid Queue** (DB-backed, no Redis) — a deliberate deviation from PrjAGWms's default in-process `async` adapter, justified by this project's much heavier background workloads (git clone, Graphify, LLM calls — all potentially multi-minute). Its own tables live on a separate local SQLite database (`config/database.yml`'s `queue` connection) because the shared MySQL 5.7 server doesn't support `SKIP LOCKED`. Run with `bin/jobs`; see `docs/setup.md` §6.

## ENV

| Variable | Required | Purpose |
|---|---|---|
| `GITHUB_ACCESS_TOKEN` | Yes | GitHub API + git clone auth |
| `LLM_PROVIDER` | No (default `gemini`) | `openai` \| `claude` \| `gemini` |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` | Yes, matching `LLM_PROVIDER` | LLM vendor auth |
| `LLM_MODEL` | No | Overrides the provider's built-in default model |
| `TEST_SCOPE_PROMPT_VERSION` | No (default `v1`) | Recorded on every `TestReport`, so a later prompt change is auditable against historical reports |
| `REPOSITORY_ROOT` | No (default `storage/repositories`) | Where cloned repos/worktrees live on disk |
| `JOB_CONCURRENCY` | No (default `1`) | Solid Queue worker process count |

DB credentials are **not** `ENV`-based — they're Rails encrypted credentials (`bin/rails credentials:edit`), matching PrjAGWms/DependencyWeb's own convention; `project_plan.md` §3's override to `ENV`-based secrets applies specifically to the GitHub/LLM secrets above, not database access. No secret is ever logged, rendered into HTML, or included in an exception message (§33/§64/§66).

## Deployment 注意事項

- **The background worker (`bin/jobs`) is not optional** — without it, every project import and PR analysis sits at `queued` forever. Run it as its own supervised process alongside the web server.
- **`storage/repositories/` needs to persist** across deploys/restarts on whatever host runs the worker — it's git-ignored (correctly — it's cloned data, not source), but losing it just means the next operation re-clones (`Repositories::Clone` is idempotent), not a hard failure. Size grows with the number of imported projects; nothing currently prunes it.
- **`uv tool install graphifyy` is a one-time host-level step**, not something a deploy script should run per-release — see `docs/setup.md` §4. Any host running the background worker needs it; the web server process doesn't (Graphify only ever runs from `PullRequestAnalysisJob`/`ProjectImportJob`).
- **MySQL 8.0+ is recommended over 5.7** for the `primary` database if starting fresh — this environment runs 5.7 for parity with `/home/micky/DependencyWeb`'s existing server, which is exactly why Solid Queue needed the separate SQLite `queue` database in the first place. A MySQL 8+ deployment could in principle collapse both onto one database, though that's a deliberate simplification this project didn't need to make.
- **No authentication layer exists** — this was out of scope per the original spec (no multi-tenant/access-control requirement), not an oversight. Don't expose this app on a network where "anyone who can reach the URL can import/delete any project and trigger PR analyses" is unacceptable, without adding one first.
