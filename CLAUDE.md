# CLAUDE.md — WebSight AI operating harness

This file is the standing operating contract for every Claude Code session
that works on this repository. It is loaded into the working context at the
top of every session and treated as authoritative.

GitHub branch protection cannot be enforced on this private repo on the
free tier. The rules below substitute for the CI gates and protected-branch
settings we would otherwise rely on. **They are not suggestions.** A rule
violation in this file should be treated with the same weight as a failing
required-status-check in a protected-branch repo.

If a future change to product direction requires loosening any rule here,
that change lands in `CLAUDE.md` first via its own PR, with the rationale
captured in the description, *before* any code that depends on the
loosening is written.

---

## 1. Authoritative documents

These six documents define the design and process for WebSight AI. When
they disagree with this file, **this file wins for process**, the spec
docs win for design.

| Doc | Authority |
|---|---|
| `AI_SPEC.md` | Vision, locked decisions, identity, release staging, PR ladder, first-PR shape. Read first every session. |
| `docs/AI_DESIGN.md` | Architecture: agent loop, providers, memory, defense pipeline, edge integration, billing modes, task-class router, YAML schema, full directory layout. |
| `docs/AI_THREAT_MODEL.md` | Threat taxonomy, defense layers, attack scenarios. Authoritative when threat-model language is in question. |
| `docs/EDGE_DEFENSE.md` | On-device defense execution architecture: Gemini Nano via AICore (v1+), Apple Foundation Models (v3.x). Tier A/B/C/A+ classification. |
| `docs/AI_TEST_STRATEGY.md` | Pyramid, fakes, security fixtures, CI gates, coverage thresholds. |
| `CONVENTIONS.md` | Code style, naming, state management, imports, `_typed<T>` config pattern, provider conventions. |

When code disagrees with spec, **surface the disagreement explicitly** in
the PR description — do not silently reconcile. Flag drift as soon as you
see it; drift compounds.

---

## 2. Locked decisions (from `AI_SPEC.md` §6 — do not casually revisit)

These are settled. Reopening any of them requires its own discussion in an
issue or PR description, not a side-comment during implementation.

- Product name: **WebSight AI**.
- Application id: **`io.github.blokzdev.websight_ai`**.
- v1 spearhead: **Wikipedia**.
- v1 minimum Android API: **34** (Android 14).
- v1 platform: **Android only**. iOS deferred to v3.x.
- Three billing modes architected from day one: **BYOK (v1 only mode)**,
  managed credits (v1.5 default), local-only (v2 on Tier A+).
- Provider scope at v1: **Anthropic, OpenAI, Google** (Anthropic recommended).
- `ai.security.edge_defense.mode`: **`auto`** with UI configurability.
- AICore download UX: **lazy** (on first edge call, with progress).
- Cloud-fallback model mapping per provider: locked per `AI_DESIGN.md` §1.5.
- Crash reporting: **asked at onboarding**.
- Self-reflection on destructive actions: **on by default**, edge-first.
- Task-class router with three UI presets (cost-conscious / balanced /
  quality-first); **`balanced` is default**.
- Preset A (co-pilot) and Preset B (browser) **share one architecture**;
  v1 builds the multi-host seams Preset B will light up in v2.

The PR ladder in `AI_SPEC.md` §7 is the v1 sequence. PRs land in roughly
that order. The first PR is **scaffolding only — no agent runtime**.

---

## 3. Branch and PR discipline

**Never commit directly to `main`.** Period. If you find yourself on
`main`, switch off it before staging a single change.

**Branch naming** (lowercased and hyphenated):
- `feature/<kebab-case>` — new functionality
- `fix/<kebab-case>` — bug fixes
- `refactor/<kebab-case>` — internal cleanups (only when the PR ladder
  authorizes them)
- `docs/<kebab-case>` — doc-only changes
- `chore/<kebab-case>` — build / tooling / dependency changes

The CI workflow already accepts pushes to `main`, `claude/**`,
`feature/**`, `fix/**`. The `claude/**` namespace is reserved for
Claude-orchestrated work in progress; PRs should still come from one of
the named prefixes above (or from a `claude/<purpose>` branch when the
work was launched by a Claude task).

**Every change lands via a pull request** from the feature branch into
`main`. No exceptions for "small" changes — every change.

**PR descriptions must include**:
1. **What changed** — bullet summary.
2. **Why** — link to the PR-ladder item from `AI_SPEC.md` §7.
3. **What was tested** — `flutter analyze`, `flutter test`, manual checks.
4. **Deviations from spec** — explicit list, or "none" with confidence
   statement.
5. **PR ladder item being addressed** — exact §7 number from `AI_SPEC.md`.

**Merge mechanics**:
- **Linear history**: squash-merge or rebase-merge, not merge commits.
  This is the AI fork's policy and overrides any earlier guidance in
  `CONVENTIONS.md` §12 that predates this file. Within a feature branch,
  keep small per-concern commits so review can follow the work; squash
  consolidates them into a single mainline commit at merge.
- **Never force-push to `main`.** Never delete `main`.
- **Never auto-merge.** Wait for explicit human approval visible in the
  PR conversation. A green CI run is necessary but not sufficient.
- **No `--no-verify`** on commits; no `--no-gpg-sign`; no skipping hooks.
  If a hook fails, fix the underlying issue, don't bypass.
- **Create new commits, not amends**, when a hook fails or a review asks
  for a change. Amend is reserved for last-step pre-push polish on
  unpushed commits.

**Drive-by changes are not allowed**. If a stale TODO, a typo, or an
obvious refactor opportunity catches your eye while working on a PR
ladder item, file it in `TODO.md` or open a separate follow-up PR.
**Never absorb it silently.**

---

## 4. Spec discipline

The six docs in §1 are authoritative. Locked decisions in §2 are not
casually revisitable.

- **When code disagrees with spec, surface the disagreement explicitly**
  in the PR description. Do not silently reconcile.
- **PR ladder ordering is roughly fixed.** Item N+1 may not depend on
  item N+2. If it does, that's a spec drift to flag; the ladder gets
  re-ordered in its own PR before the work proceeds.
- **The first PR is scaffolding only** — no agent runtime, no provider
  adapters, no JS bridge agent extensions, no dock or panel UI, no
  memory implementations, no router logic, no billing logic. See
  `AI_SPEC.md` §7 for the exhaustive in-scope/out-of-scope list.
- **The locked YAML schema in `AI_DESIGN.md` §10 is the contract.** The
  scaffolded `ai_config.dart` parses every block (`ai.security.*`,
  `ai.edge_defense.*`, `ai.billing.*`, `ai.router.*`) even if no code
  reads them yet. **`ai.billing.mode` accepts `byok | managed | local`
  but only `byok` is honored in v1**; the others reject with a clear
  "not yet supported" error.
- **The two-axis autonomy model is non-negotiable.** Sensitive fills
  (password, card, ssn, pin) always confirm; this is locked in code and
  not user-configurable.
- **Defense in depth is non-negotiable.** Sanitization, spotlighting,
  flow tagging, classifier, optional paraphrasing, self-reflection.
  Don't ship one defense alone.
- **Deterministic security stays deterministic.** `_onNavigationRequest`
  in `lib/webview/webview_controller.dart:497` and the bridge origin
  gate in `_isOriginAllowed` (`lib/bridge/js_bridge.dart`) are
  backstops. The agent's `navigate` tool is a redundant gate, never a
  replacement.

---

## 5. Code discipline

Every PR must:

1. Pass **`dart format --set-exit-if-changed lib test tool`** (CI gate).
2. Pass **`flutter analyze --no-fatal-infos`** with zero errors and zero
   warnings (CI gate; note CI tolerates info-level lints, but new code
   should be clean of those too).
3. Pass **`flutter test --coverage`** with all existing tests green
   (CI gate).
4. Pass the **manifest sanity check** in `.github/workflows/ci.yml`.
5. Pass the **debug Android build** step (CI gate).
6. **Add tests for new code paths** per `docs/AI_TEST_STRATEGY.md`. A
   feature without tests is unfinished. Coverage thresholds (`lib/ai/`
   85%, `lib/ai/memory/` 90%, `lib/config/ai_config.dart` 95%, etc.) are
   enforced from the PR they apply to onward.

**Existing CI must remain green throughout.** Never disable a check to
land a PR. If a check is wrong, fix the check in its own PR.

**Configuration parsing follows `feature_configs.dart`'s `_typed<T>`
pattern.** No new code goes through `json_serializable` /
`build_runner`. (`webview_config.dart` and `webview_config.g.dart`
remain on the legacy pattern; new feature configs are hand-rolled.)

**Imports follow `analysis_options.yaml`**: `always_use_package_imports`
is enforced. After the rename, all imports use `package:websight_ai/...`,
not relative paths (except in `tool/`, where the existing precedent
holds).

**No secrets in commits, ever**. API keys, tokens, account credentials,
service-account JSON, signing certificates — none of it goes in source
control.
- Runtime: `flutter_secure_storage` only. Never YAML, never
  `shared_preferences`, never in transcripts or audit logs.
- YAML defaults: placeholder values only. The provider security-posture
  block in `webview_config.yaml` carries metadata, never keys.
- If a real key is ever committed: **treat it as compromised, rotate
  immediately**, and remove it from history (force-push exception
  authorized only in this case, with explicit user approval and a
  documented incident report).

---

## 6. Communication protocol

- **Surface ambiguity before writing code** that depends on its
  resolution. Never silently choose between two reasonable
  interpretations of the spec.
- **Flag deviations from locked decisions explicitly** in the PR
  description.
- **When stuck, stop and ask** rather than guess. The cost of a 30-
  second clarification is far below the cost of a wrong implementation.
- **Restate the goal in your own words** before starting on a non-
  trivial PR; the user can correct your mental model before code is
  written.
- **Do not invent design** when the spec is silent on something
  load-bearing — flag it, ask, and document the decision back into
  the relevant spec doc as part of the PR.

---

## 7. Session hygiene

**At the start of every session**:

1. Read this file (`CLAUDE.md`) end-to-end.
2. Re-read `AI_SPEC.md` §6 (locked decisions) and §7 (PR ladder).
3. Run `git status` and `git branch --show-current`. Confirm you are not
   on `main`.
4. Check the open PR list (`gh pr list` or via the GitHub MCP tools).
5. Check CI status of the most recent PR if any.
6. Produce a brief "where I left off" summary: current branch, last
   commit, current PR ladder item, blockers if any.

**At the end of every session**:

1. Summarize what was done: branch state, files changed, PRs opened or
   updated, tests added.
2. Summarize what's pending: next planned step, any in-flight work that
   isn't checkpointed.
3. List any open questions or blocked items so the next session picks
   up cleanly.

**Mid-session checkpoints** (see §10): every meaningful unit of work is
committed before moving on, even within a feature branch. A session that
times out mid-work should leave the branch in a state the next session
can reason about.

---

## 8. Scope discipline

**Each PR addresses one concern from the PR ladder.** Tempting cleanups
that aren't on the ladder do not justify scope creep.

- Stale TODOs noticed during work → file in `TODO.md` (create if missing)
  with a short note and the file:line reference.
- Refactor opportunities outside the current PR's scope → separate PR,
  or a follow-up note in the current PR description.
- Optimization opportunities → separate PR, *only if* on the ladder or
  blocking the current ladder item.
- Drive-by formatting changes → not allowed. CI's format check enforces
  consistency; manual reformat of unrelated files generates noise.

If the work expands beyond the ladder item's natural scope, **stop and
flag** rather than continue. Better to ship a smaller PR and file a
follow-up than to ship a sprawling one that's hard to review.

---

## 9. Failure handling

- **When tests fail and the fix isn't obvious within ~3 attempts: stop
  and surface the issue.** Do not enter a "try-this-try-that" debugging
  loop without communicating. The user would rather see "I'm stuck on
  X, here's what I've tried, here's what I think is happening" than a
  10-minute silence.
- **When spec ambiguity blocks progress: stop and ask.** Do not pick
  one interpretation and proceed.
- **When a change is touching more files than the PR ladder item
  implies: stop and flag potential scope creep** before continuing.
  Examples: a "fix YAML parsing" PR shouldn't be touching the agent
  loop. A "add Anthropic adapter" PR shouldn't be touching memory.
- **When CI fails on a PR**: investigate the root cause; do not push
  fixups in a frenzy. If the CI failure is genuinely unclear, surface
  the logs and ask before retrying.
- **Never use destructive operations as a shortcut to make an obstacle
  go away.** `git reset --hard`, `git push --force`, `rm -rf`, dropping
  database tables, killing processes — all require explicit
  authorization in context.

---

## 10. Progress checkpointing

Long deliverables — substantive plans, multi-section documentation,
large refactors, multi-file changes — are produced in **checkpoints**,
not monolithic outputs.

- **Code**: large multi-file changes are committed as logical sub-
  commits within the feature branch, not amassed into one giant commit
  at PR time. Each sub-commit should be a coherent reviewable unit.
- **Documentation**: long docs are produced section-by-section, with
  brief checkpoint messages between sections so the user can redirect
  at natural boundaries.
- **Analysis**: long analysis tasks are produced as labeled chunks (as
  in this first session), not as one continuous wall.

Between checkpoints, briefly state what's complete and what's next.
This protects against session interruption (mobile network drops,
backgrounding, timeouts) and lets the human reviewer redirect at
natural boundaries rather than read a wall before pushing back.

---

## 11. Escalation asymmetry

**Escalate liberally on**:
- Architecture decisions (especially anything that touches
  `AI_SPEC.md` §6 locked decisions or invalidates the Preset-B-readiness
  invariants in `AI_DESIGN.md` §1.3).
- Autonomy / permission decisions (e.g., relaxing the always-confirm
  list, changing flow-check sink rules, expanding the agent's tool
  surface).
- Security or privacy decisions (anything affecting `flutter_secure_
  storage` use, audit log content, telemetry posture, edge vs cloud
  routing).
- Threat-model implications (anything that might widen the attack
  surface or weaken a defense layer).
- Billing / credential decisions (BYOK vs managed vs local routing,
  credential storage, cross-provider mixing).

**Escalate moderately on**:
- UX surfaces visible to users (dock placement, chat panel layout,
  confirm sheet copy, onboarding screen ordering).
- User-facing copy (privacy explainer, error messages, capability
  warnings).
- Naming of public APIs (provider class names, tool names, YAML keys).
- Configuration defaults (token budget thresholds, retention policies,
  classifier mode).

**Decide independently within `CONVENTIONS.md` on**:
- Local code style and idioms (`final` vs `var`, comment phrasing).
- Internal helper naming (private methods, file-scope utilities).
- Test data fixtures (synthetic names, seed values).
- Refactor patterns within a single file (when the refactor is on the
  ladder).
- Choice between two equivalently-conventional implementations.

When in doubt, escalate. The cost of a brief check-in is well below the
cost of an undone-and-redone implementation.

---

## 12. Quick reference: PR checklist

Before opening a PR, confirm:

- [ ] Branch is `feature/`, `fix/`, `refactor/`, `docs/`, `chore/`, or
      `claude/<purpose>` — not `main`.
- [ ] Commit history is logical (small commits per concern, not one
      blob).
- [ ] `dart format --set-exit-if-changed lib test tool` clean.
- [ ] `flutter analyze --no-fatal-infos` clean (zero errors, zero
      warnings).
- [ ] `flutter test --coverage` green; new code paths have tests.
- [ ] Existing CI gates pass locally (debug Android build, manifest
      sanity check).
- [ ] PR description includes: what / why / what was tested /
      deviations / PR ladder item.
- [ ] No secrets in the diff (grep your own changes for `sk-`, `api`,
      `key`, `token`, `secret` before pushing).
- [ ] No `print()` or unguarded `debugPrint` in production paths.
- [ ] No commented-out code (per `CONVENTIONS.md` §8).
- [ ] No drive-by changes outside the PR's stated scope.
- [ ] If touching the agent loop or defense pipeline: flow tags
      preserved, sink rules unchanged, audit log entries complete.
- [ ] If touching YAML schema: `ai_config.dart` parsing tests updated.

---

## 13. Quick reference: substrate file map

The existing WebSight extension points (do not bypass):

| Concept | File | Notes |
|---|---|---|
| JS bridge dispatch (Dart) | `lib/bridge/js_bridge.dart` | Origin-gated by `_isOriginAllowed` |
| JS bridge surface (page) | `assets/websight.js` | `WebSightBridgeInternal` |
| ActionDispatcher | `lib/shell/action_dispatcher.dart` | New `agent.*` grammar lands here |
| AppShell stack | `lib/shell/app_shell.dart` | Dock + chat panel layer here |
| Configurable native screen | `lib/native_screens/configurable_native_screen.dart` | New `/native/ai-*` routes |
| WebView controller + delegate | `lib/webview/webview_controller.dart` | `_onNavigationRequest` at line 497 — deterministic backstop |
| Bridge origin gate | `lib/bridge/js_bridge.dart::_isOriginAllowed` | Drops bridge calls from disallowed origins |
| Hand-rolled config parser | `lib/config/feature_configs.dart` | `_typed<T>` pattern; new `ai_config.dart` follows this |
| Existing typed config | `lib/config/webview_config.dart` (+ `.g.dart`) | Legacy `json_serializable`; do not extend |
| Demo YAML | `assets/webview_config.yaml` | Add `ai:` block here |
| Canonical YAML reference | `docs/internal/config-reference.yaml` | |
| Android entry | `android/app/src/main/kotlin/com/app/websight/MainActivity.kt` | Migrates to `io/github/blokzdev/websight_ai/` in the rename PR |
| Android build config | `android/app/build.gradle.kts` | minSdk bumps to 34 in the rename PR |

The new directories created by the first scaffolding PR (per
`AI_SPEC.md` §7, plus `lib/ai/site_profiles/` and `lib/ai/tools/`
which appear in `AI_DESIGN.md` §1.1 and are v1 scope):
`lib/ai/`, `lib/ai/edge/`, `lib/ai/router/`, `lib/ai/billing/`,
`lib/ai/memory/`, `lib/ai/providers/`, `lib/ai/site_profiles/`,
`lib/ai/tools/`, `lib/ai_ui/`, `lib/ai_ui/onboarding/`,
`lib/ai_ui/settings/`. Each new dir gets a `.gitkeep` until its first
real file lands.

---

## 14. Quick reference: definitions

- **Tier A** — AICore-enabled Android device (Pixel 8+, Galaxy S24+,
  ~140M+ devices). Defense ops run on-device.
- **Tier A+** — Tier A plus hardware sufficient for sustained agent
  reasoning (Pixel 10+, Galaxy S26+, Nano 3+, NPU, 8GB+ RAM). Required
  for v2 local-only mode.
- **Tier B** — Android 14+ without AICore. Cloud fallback for ML defense
  ops; sanitization / spotlighting / flow tagging still work.
- **Tier C** — Below Android 14. AI build cannot install; user stays on
  plain WebSight.
- **Preset A** — Co-pilot for one wrapped app (v1 = Wikipedia).
- **Preset B** — Open-web AI browser (v2).
- **BYOK** — Bring your own key (v1 only billing mode).
- **Managed credits** — Server-proxy credit system (v1.5).
- **Local-only** — Fully on-device inference (v2 on Tier A+).
- **Routine / Reasoning / Heavy** — Task-class router buckets driving
  per-turn model selection.
- **Flow tags** — `user_typed`, `page_content`, `memory`, `tool_result`.
  Carried with every value in the agent's working context. Sink rules
  enforce flow-control at the action layer.

---

## 15. Living document

This file evolves as the work does. Updates are PRs of their own (per §3).
When new conventions emerge, when locked decisions change, when a
release lights up a new capability — `CLAUDE.md` is updated to reflect
the current state of the world before the dependent code lands.

When this file conflicts with current code, current code is the bug:
either fix the code or update this file deliberately. Don't let drift
sit.
