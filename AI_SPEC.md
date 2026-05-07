# WebSight-AI: Kickoff Spec

Decisions captured. Open questions in §6 are scoped to specific releases.

**Identity:**
- Product name: **WebSight AI**
- Application id: **`io.github.blokzdev.websight_ai`** (GitHub-derived; migrate to a domain-derived id only if/when a real brand emerges)
- v1 spearhead: **Wikipedia co-pilot**
- v1 minimum Android API: **34** (Android 14)
- v1 platform: **Android only**

**Document map:**
- This file — vision, presets, extension points, working constraints, first session task, first PR. Read this first.
- [`docs/AI_DESIGN.md`](docs/AI_DESIGN.md) — full architecture: agent loop, toolkit, memory, host enforcement, defense pipeline, YAML schema, autonomy model, cost & latency, edge integration, billing modes, task-class router.
- [`docs/AI_THREAT_MODEL.md`](docs/AI_THREAT_MODEL.md) — what we defend against, the layered defense architecture, attack scenarios, and limitations. Authoritative when threat-model language is in question.
- [`docs/EDGE_DEFENSE.md`](docs/EDGE_DEFENSE.md) — how the defense layer runs on-device wherever possible (Gemini Nano via AICore on Android in v1; Apple Foundation Models on iOS in v3.x), with cloud fallback. Cost and privacy implications. Tier A+ classification for v2 local-only mode.
- [`CONVENTIONS.md`](CONVENTIONS.md) — coding and structural conventions inherited from WebSight, made explicit.
- [`docs/AI_TEST_STRATEGY.md`](docs/AI_TEST_STRATEGY.md) — test pyramid, fake-provider design, adversarial security fixtures, billing/router test surfaces, CI expectations.

---

## 1. Vision

WebSight-AI is the AI-native variant of WebSight. It keeps the proven substrate — a Flutter Android WebView shell driven by `assets/webview_config.yaml` with a hardened JS bridge, deterministic host enforcement, and a config-first philosophy — and layers on:

- A **floating, hideable chat dock** that overlays the WebView without breaking the wrapped site's UX.
- An **expandable chat panel** for conversation, tool-call traces, and confirmation prompts.
- An **aware AI agent** that reads the current page and performs actions through an extended JS bridge, constrained by host allowlists and a destructive-action policy.
- **Defense-in-depth against indirect prompt injection.** Sanitization, spotlighting, retrieved-data classification, optional paraphrasing, information-flow tagging, and self-reflection on destructive actions. Most defense layers run on-device (Gemini Nano via AICore on Tier A Android devices) with cloud fallback. See [`AI_THREAT_MODEL.md`](docs/AI_THREAT_MODEL.md) and [`EDGE_DEFENSE.md`](docs/EDGE_DEFENSE.md).
- **Three billing modes architected from day one**, shipped progressively: BYOK (v1, default at launch), managed credits (v1.5, becomes default for new installs), local-only on Tier A+ devices (v2). All three use the same agent loop and defense layer; mode selection is purely *which `AgentProvider` instance the loop talks to*.
- **Task-class model routing.** Routine page reads, reasoning tasks, and heavy work (skill creation, multi-step planning, code generation) route to different model tiers per provider. Three UI presets — cost-conscious, balanced (default), quality-first — with per-class overrides for power users.
- **A reading-shaped agentic toolkit.** v1's tools (save_article, summarize_section, follow_citations, extract_claims, build_topic_map, compare_articles, find_contradictions) are designed to be reading-general, not Wikipedia-specific. They seed v2's open-web generic mode rather than getting thrown away.

We are building a premier, world-class scalable foundation in v1 — not a minimum viable proof. The architecture choices below reflect that: full provider parity, real semantic memory with auto-extraction, robust autonomy controls, layered defenses against indirect prompt injection from launch, three-mode billing readiness, task-class routing, and proper test coverage from day one.

The agent is constrained by deterministic guarantees — host allowlists, the destructive-action policy, the audit log, the information-flow rules — not because we don't trust the model, but because deterministic guarantees are what make an agent safe to ship to users who didn't write the system prompt.

**v1 spearhead: Wikipedia.** No official mobile app, well-defined pain points (long articles, citation chains, cross-topic connections, disambiguation, edit history), curated low-adversarial content, supportive ecosystem (Wikimedia Foundation), and — most importantly — a toolkit that generalizes. Every tool we ship for Wikipedia is a tool v2's generic mode inherits. v1 launch posture is "ship a product whose threat surface is forgiving by design," letting the defense layer accumulate real-world telemetry before harder cases (Stack Overflow, Reddit) come online in subsequent releases.

---

## 2. Preset strategy (locked)

Two products, **one architecture**. Developer chooses experience at build time via `ai.preset`. **Users do not toggle between presets.**

- **Preset A — Co-pilot for a wrapped app.** v1 spearhead (Wikipedia), v1.x (Stack Overflow), v1.y (Reddit). YAML pins `security.restrict_to_hosts` to one host or first-party set. The agent is a power-user companion *inside* that app. Each shipped co-pilot is its own product with its own marketing.
- **Preset B — AI-native browser.** v2 product, separate ship. User-configurable home URL, additive trusted domains, broad navigation. Bundled with site profiles accumulated from shipped Preset A co-pilots, plus first-visit profile generation and skill learning for previously-unseen sites.

**Both presets share the same architecture.** v1 builds the multi-host site-profile registry, the per-host autonomy map, the wildcard host matcher, the system-prompt composer, and the per-host memory router — but ships them with one entry / one host / one profile. v2 flips switches; no rewrite. See `AI_DESIGN.md` §1.3 for the explicit shared-architecture invariants v1 must preserve.

The site-profile flywheel: every shipped co-pilot accumulates engineering-derived knowledge (tuned system prompt, DOM heuristics, named workflows, trusted-domain list). We package these as bundles. The browser ships with the accumulated bundles plus generic-mode fallback. **Site profiles in v1–v1.y are dev-team-authored, not user-data-derived.** Skill learning in v2 is opt-in and runs on-device (no first-party telemetry on conversation content, ever — see `AI_DESIGN.md` §10).

---

## 3. What we inherit from WebSight (extension points)

Every new feature hooks into one of these. None of them are bypassed.

| Extension point | Where it lives | What we extend it for |
|---|---|---|
| **JS bridge** | `lib/bridge/js_bridge.dart` + `assets/websight.js` | Agent's hands. New methods: `readPage`, `screenshot`, `click`, `fill`, `scroll`, `waitFor`, `getState`. |
| **ActionDispatcher** | `lib/shell/action_dispatcher.dart` | Add `agent.*` grammar (`agent.toggle_dock`, `agent.run`, `agent.clear_session`). |
| **AppShell stack** | `lib/shell/app_shell.dart` | Floating dock + chat panel as new Stack children. |
| **ConfigurableNativeScreen** | `lib/native_screens/configurable_native_screen.dart` | Add `/native/onboarding`, `/native/ai-settings`, `/native/audit-log`, `/native/memory`. |
| **NavigationDelegate** | `_onNavigationRequest` in `lib/webview/webview_controller.dart` | Stays as the deterministic backstop. The agent's `navigate` tool is an additional, redundant gate — not a replacement. |

The YAML schema is the implicit sixth point: new config under an `ai:` block in `webview_config.yaml`, parsed via the existing hand-rolled `_typed<T>` pattern. No `build_runner`.

---

## 4. Working constraints (non-negotiable)

These rules apply to every PR, every file, every change. Don't break them quietly.

- **Single source of truth.** New config goes under `ai:` in `assets/webview_config.yaml`. Parsed via the `_typed<T>` map-extraction pattern from `feature_configs.dart`. No `build_runner` for new features.
- **Deterministic security stays deterministic.** `_onNavigationRequest` and `_isOriginAllowed` are backstops. The agent's `navigate` tool is a redundant gate, never a replacement. The model is told the policy in the system prompt as UX, never as enforcement.
- **No browser storage in injected scripts.** `ai_agent.js` and anything passed to `runJavaScript` is stateless. No `localStorage`, no `sessionStorage`, no `indexedDB`, no cookie writes. All agent state lives Dart-side. (Reasons in `AI_DESIGN.md` §8.)
- **Keys never in YAML or `shared_preferences`.** `flutter_secure_storage` only.
- **Local-first, period.** No first-party telemetry on conversation content. Crash reporting (existing `analytics_crash` config) is allowed for non-content errors only and must be disclosed in onboarding (see `AI_DESIGN.md` §9).
- **Audit log everything.** Every navigation attempt (allowed and blocked), every destructive action (confirmed and denied), every tool call (with redacted args). Surfaced in settings.
- **Match WebSight's code style.** See `CONVENTIONS.md`.
- **Plan before coding.** New features land as: design note in `docs/AI_*.md` → skeleton files with TODOs and tests → implementation. Not the reverse.
- **Test coverage is part of done.** A feature without tests is unfinished. See `docs/AI_TEST_STRATEGY.md`.

---

## 5. First session task (for Claude Code)

**Do this first, before writing any code or modifying any files:**

1. **Read the substrate.**
   - `README.md`, `docs/BLUEPRINT.md`, `docs/ROADMAP.md`, `docs/bridge-api.md`, `docs/internal/config-reference.yaml`, `CHANGELOG.md`
   - `lib/config/`, `lib/shell/`, `lib/webview/`, `lib/bridge/`, `lib/native_screens/`, `lib/lifecycle/`
   - `assets/websight.js`, `assets/webview_config.yaml`
   - `android/app/src/main/kotlin/com/app/websight/`

2. **Read the spec docs.** `AI_SPEC.md` (this file), `docs/AI_DESIGN.md`, `docs/AI_THREAT_MODEL.md`, `docs/EDGE_DEFENSE.md`, `CONVENTIONS.md`, `docs/AI_TEST_STRATEGY.md`.

3. **Confirm understanding.** In one page:
   - What WebSight currently does (1 paragraph)
   - The five extension points from §3 above, in your own words, with file:line pointers
   - Anything in the spec that doesn't match the actual code (call out spec drift now)
   - Anything in the spec that's underspecified for you to act on

4. **Propose the rename plan.** Enumerate `websight` → `websight_ai` mechanical changes with file paths and counts. Don't apply yet.

5. **Surface clarifying questions.** Beyond the open questions in §6 — anything ambiguous in the design that would block your first PR.

**Do not** create new files, modify existing files, run builds, or run `tool/configure.dart` in this turn. Output: substrate summary + spec-drift callouts + rename enumeration + clarifying questions.

---

## 6. Open questions (mostly resolved)

Tagged by blocking status:

- `[BLOCKS first PR]` — must answer before first code lands
- `[BLOCKS v1]` — must answer before v1 ships
- `[BLOCKS v1.x / v1.5 / v2 / v3.x]` — release-specific
- `[INFORMS]` — useful but not gating

**Locked decisions:**
- ✅ v1 demo target: **Wikipedia**
- ✅ App identity: `io.github.blokzdev.websight_ai`, product "WebSight AI"
- ✅ Min Android API: **34** (Android 14)
- ✅ `ai.security.edge_defense.mode`: **`auto`**, with UI configurability surfaced in AI Settings
- ✅ AICore download UX: **lazy** (on first edge call, with progress indicator)
- ✅ Cloud-fallback model mapping per provider — locked per-tier per `AI_DESIGN.md` §X.3:
  - Anthropic: routine→Haiku 4.5, reasoning→Sonnet 4.6, heavy→Opus 4.7
  - OpenAI: routine→GPT-5-Nano, reasoning→GPT-5-Mini, heavy→GPT-5
  - Google: routine→Flash, reasoning→Pro, heavy→Pro (with thinking mode)
- ✅ Three billing modes; v1 ships BYOK only with architectural readiness for managed (v1.5) and local-only (v2)
- ✅ Task-class router with three UI presets (cost-conscious / balanced / quality-first)
- ✅ iOS pushed to **v3.x** (Apple Foundation Models)
- ✅ Provider scope: all three (Anthropic, OpenAI, Google) at v1
- ✅ Crash reporting: **asked at onboarding**
- ✅ Self-reflection on destructive actions: **on by default**, edge-first execution

**Still open, scoped to release:**

- `[BLOCKS v1]` Episodic retention default — recommend forever-with-manual-delete; user can configure in Memory settings.
- `[BLOCKS v1]` Auto-extraction review UX — recommend auto-suggest with batched user review (not per-fact friction); user can flip to per-fact in settings.
- `[BLOCKS v1]` Embeddings provider when chat provider lacks them (Anthropic) — recommend default to Voyage; user can pick at onboarding. Confirm before first PR.
- `[BLOCKS v1]` Default model per provider in `routine` class — confirm Haiku 4.5 / GPT-5-Nano / Gemini Flash mapping is current at ship date.
- `[BLOCKS v1]` Set-of-Marks injection — recommend only when agent calls `screenshot`. Confirm before agent-loop PR.
- `[BLOCKS v1]` Play Store distribution from v1 launch (vs sideload-only beta first) — recommend Play Store; v1 is BYOK so no managed-billing complications.
- `[BLOCKS v1.x]` Streaming text deltas from user to agent — defer.
- `[BLOCKS v1.x]` Site-profile bundle format — defer until Stack Overflow forces the schema.
- `[BLOCKS v1.x]` Memory export format (JSON vs Markdown vs both).
- `[BLOCKS v1.5]` Managed-billing pricing tiers, credit-pack sizes, free-trial credit allocation.
- `[BLOCKS v1.5]` Server-side proxy hosting (Cloudflare Workers, Fly.io, GCP Cloud Run, etc.).
- `[BLOCKS v1.5]` Account system: OAuth-only (Google/Apple sign-in) vs email-password.
- `[BLOCKS v2]` Local-only mode minimum-quality bar — what task classes do we explicitly tell users will degrade?
- `[BLOCKS v2]` Skill-learning opt-in default and review UX.
- `[BLOCKS v2]` First-visit profile generation — purely on-device or cloud-assisted with user opt-in?
- `[INFORMS]` Anonymous usage telemetry (counts only, no content) — recommend off, no toggle in v1; revisit at v1.5 if it would help managed-tier capacity planning.
- `[INFORMS]` Open-source the AI variant like WebSight or keep proprietary — recommend keep private through v1.x; reconsider once managed-billing infrastructure is mature and the open-source story is well-defined.

---

## 7. First PR (definition)

After Claude Code's first session output (substrate summary + rename plan + clarifying questions), the first mergeable PR is **scaffolding only — no agent runtime yet**.

**In scope:**
- Repo rename: `websight` → `websight_ai`. pubspec name, all Dart imports, asset paths, README, CI badges.
- App identity: application id set to `io.github.blokzdev.websight_ai` in `android/app/build.gradle`. Product name "WebSight AI" in manifest label and store listing copy.
- New empty directories:
  - `lib/ai/`, `lib/ai/edge/`, `lib/ai/router/`, `lib/ai/billing/`, `lib/ai/memory/`, `lib/ai/providers/`
  - `lib/ai_ui/`, `lib/ai_ui/onboarding/`, `lib/ai_ui/settings/`
- New empty asset: `assets/ai_agent.js` (header comment + empty IIFE).
- `lib/config/ai_config.dart` — parsed `ai:` block (schema scaffold; `enabled: false` by default; loader + tests). Schema includes `ai.security.*`, `ai.edge_defense.*`, `ai.billing.*`, and `ai.router.*` blocks even if unused at this stage. `ai.billing.mode` accepts `byok | managed | local`; only `byok` is honored in v1.
- `assets/webview_config.yaml` — append the `ai:` block (`enabled: false` default, `billing.mode: byok`), so the parser exercises the new schema.
- Three new route stubs in `ConfigurableNativeScreen`: `/native/ai-settings`, `/native/onboarding`, `/native/audit-log`. Each renders a labeled placeholder.
- Min Android API bumped to 34 (Android 14) for the AI build (per `EDGE_DEFENSE.md` §9).
- Tests for `ai_config.dart` parsing including the new blocks.
- All six docs checked into the repo: `AI_SPEC.md`, `docs/AI_DESIGN.md`, `docs/AI_THREAT_MODEL.md`, `docs/EDGE_DEFENSE.md`, `docs/AI_TEST_STRATEGY.md`, `CONVENTIONS.md`.

**Out of scope (deferred to subsequent PRs):**
- Any agent loop code
- Any provider adapters (cloud or edge)
- Any JS bridge agent extensions
- The floating dock / chat panel
- Real onboarding flow logic
- Memory store implementations
- Task-class router logic (`lib/ai/router/` ships empty in PR 1; routing logic lands in PR 19 below)
- Billing-mode logic (`lib/ai/billing/` ships empty in PR 1; managed-mode lands in v1.5)

**Why this shape:** The first PR establishes the skeleton, validates the YAML parsing for every block we'll need across v1–v3.x, and gives every subsequent PR a clear place to land. It's small, reviewable, ships green CI, and can't break the existing WebSight functionality (because `ai.enabled: false` is the default).

**PR ladder after the first** (rough order, each independently shippable). Items grouped by which release they unlock:

*v1 — foundation, BYOK, Wikipedia:*
1. Provider abstraction (`AgentProvider` + `EdgeDefenseProvider` interfaces) + Anthropic adapter + `InMemoryAgentProvider` + `InMemoryEdgeProvider` for tests
2. BYOK secret store + `CredentialStore` abstraction (with `byok_keys` mode wired, `managed_session_token` mode stubbed) + onboarding flow (BYOK branch only; branch point exists for managed/local)
3. JS bridge agent extensions + `ai_agent.js` (`readPage`, `screenshot`, `click`, `fill`) — **with sanitization pipeline inlined from day one** (per `AI_THREAT_MODEL.md` §4.5)
4. Information-flow tagging primitives (`flow_tag.dart`, `flow_check.dart`) — required by every action-class PR after this
5. Spotlighting wrapper + system prompt scaffolding for `<untrusted_content>` boundaries
6. Agent loop skeleton with hot context — flow tags wired through
7. Floating dock + chat panel UI (no agent wiring yet)
8. Wire dock + panel to the agent loop
9. Two-layer navigation enforcement + wildcard/PSL matcher (built for multi-host even though v1 uses one)
10. Core memory + Episodic memory (FTS5) — provenance fields baked into the schema; per-host scoping plumbed
11. Memory router (heuristic) — origin-trust-aware retrieval; takes `host` parameter even in single-host v1
12. Two-axis autonomy model + confirm sheet — flow-check-aware; per-host autonomy map (one entry in v1)
13. Audit log + audit log page — full provenance trails
14. AI settings page + memory page (with stubs for managed-billing UI and local-only UI that show "coming in v1.5/v2")
15. `EdgeDefenseProvider` abstraction wiring + `CloudFallbackEdgeProvider` — required for next two PRs
16. Retrieved-data classifier (cloud fallback first; edge-first lands in PR 18)
17. Self-reflection on destructive actions
18. `AICoreEdgeProvider` (Android Gemini Nano via ML Kit GenAI) + `DefenseCoordinator` routing + Tier A+ classification stub
19. **Task-class router** (`lib/ai/router/`): task classifier + model router + three UI presets
20. Token-budget cost discipline (per task-class budget surfacing in chat-panel routing badges)
21. Vector embeddings (Episodic + Semantic similarity)
22. Auto-extraction with review UX — origin trust visible
23. Optional paraphrasing layer (off by default; opt-in per host)
24. OpenAI + Google adapters
25. **Wikipedia site profile** — system prompt, DOM heuristics, autonomy preferences, the v1 generic-reading toolkit (save_article, summarize_section, follow_citations, extract_claims, build_topic_map, compare_articles, find_contradictions)
26. Adversarial security test suite — full §5 scenarios from `AI_THREAT_MODEL.md` running in CI
27. Polish, perf, **v1 Play Store launch** (BYOK)

*v1.x — Stack Overflow co-pilot:*
28. Stack Overflow site profile — system prompt, DOM heuristics, autonomy preferences, SO-specific tool surface (accepted-answer extraction, code-block isolation, duplicate detection)
29. Site-profile bundle format crystallized (forced by having two sites)
30. Memory export (JSON + Markdown)
31. Streaming text deltas from user to agent (UX polish)

*v1.5 — managed billing infrastructure:*
32. Server-side proxy (LLM provider key holder, request meter, abuse detection, rate limiter)
33. Account system (OAuth via Google/Apple Sign-in)
34. `ManagedAgentProvider` adapter (talks to server-side proxy via session token)
35. Play Billing integration (credit packs, IAP, receipt validation)
36. Onboarding's managed-mode branch wired up; managed becomes default for new installs
37. AI Settings: managed-mode UI (credit balance, top-up, billing history), BYOK relegated to "advanced" section
38. v1.5 launch posture — "now with managed credits, no API key required"

*v1.y — Reddit co-pilot:*
39. Reddit site profile — system prompt, DOM heuristics, interstitial-dismissal, troll-aware ranking, OP-vs-replies handling
40. Defense layer telemetry review based on Wikipedia/SO production data; tune classifier and reflection thresholds
41. Per-host preference editor UI v2

*v2 — Preset B, local-only, skill learning:*
42. Preset B build flag wired up; URL bar UI; multi-tab UX; broad navigation
43. **Generic-mode fallback** — base system prompt + base tool set + base SoM heuristics for hosts without a profile
44. **First-visit profile generation** — agent observes page structure and produces a baseline profile on first load
45. **Skill learning** — auto-extraction of site patterns from observed user sessions, with on-device review UX and promotion gates
46. Universal site-profile adapter pattern (composes hand-tuned profiles + first-visit profiles + skill-learned refinements)
47. **`LocalEdgeAgentProvider`** — promotes Gemini Nano from defense-layer-only to agent-reasoning use, gated by Tier A+
48. Onboarding's local-only branch wired up; offered to Tier A+ devices alongside managed
49. AI Settings: local-only mode UI (capability indicator, quality vs cost tradeoff explanation, mode-switch flow)

*v3.x — iOS support:*
50. WKWebView shell, ATT consent, App Store metadata, signing
51. `AppleFoundationEdgeProvider` (defense layer + local-only on iOS 18+ devices with required hardware)
52. iOS-specific bridge implementation, navigation delegate, screenshot capture
53. Apple App Store launch

Each PR has its own tests; no PR breaks `flutter analyze` or the existing CI gate.

---

## 8. Release staging (locked)

| Release | Theme | New capabilities | Billing modes |
|---|---|---|---|
| **v1** | Foundation + Wikipedia | Defense layer (sanitization, spotlighting, classifier, paraphrase, flow tagging, self-reflection), edge defense via Gemini Nano, three providers (Anthropic/OpenAI/Google), full memory architecture, two-axis autonomy, audit log, task-class router, **Wikipedia co-pilot** | BYOK only; architecture supports all three |
| **v1.x** | Stack Overflow + polish | Stack Overflow co-pilot, site-profile bundle format crystallized, streaming UX, memory export | BYOK |
| **v1.5** | Managed billing | Server-side proxy, account system, Play Billing, `ManagedAgentProvider`, managed becomes default for new installs | **Managed (default)** + BYOK |
| **v1.y** | Reddit | Reddit co-pilot, defense-layer telemetry-driven tuning, per-host pref editor v2 | Managed + BYOK |
| **v2** | Preset B + local-only + skill learning | Preset B (open-web AI browser), generic-mode fallback, first-visit profile generation, skill learning, universal adapter pattern, multi-tab UX, **`LocalEdgeAgentProvider`** for Tier A+ devices | Managed + **Local-only (Tier A+)** + BYOK |
| **v3.x** | iOS | WKWebView shell, App Store launch, `AppleFoundationEdgeProvider` for both defense and local-only on iOS | All three on iOS too |

The architecture stays consistent across all six releases — v1 builds the seams that v1.5 / v2 / v3.x light up. No retrofit, no rewrite, no migration of the install base. Each release ships its own marketing moment with a focused story.
