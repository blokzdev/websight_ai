# WebSight-AI: Test Strategy

How we test the agent. What gets tested at which level. What fakes exist. What CI enforces.

Read [`AI_SPEC.md`](../AI_SPEC.md) for kickoff context, [`AI_DESIGN.md`](AI_DESIGN.md) for what's being tested, [`CONVENTIONS.md`](../CONVENTIONS.md) for naming and structure.

---

## 1. The pyramid

```
                    [ Integration ]
                  Few. End-to-end task flows through fake provider.

              [ Widget tests ]
       Some. Dock, panel, confirm sheet, settings pages, onboarding.

    [ Unit tests ]
  Many. Memory router, host matcher, autonomy policy, cost tracker,
  config parsing, redaction, page-reader serializers.

[ Static / golden tests ]
Most. Provider response fixtures → AgentEvent stream golden files.
```

The pyramid shape matters. Each provider has dozens of canned response fixtures driving golden tests. Memory and routing have hundreds of unit tests. Widget tests cover every UI surface. Integration tests are small in number but each one exercises a complete, realistic task.

---

## 2. The fake provider

The single most important piece of test infrastructure. Lives at `lib/ai/providers/fake.dart` and is the only provider used in agent-loop tests.

```dart
class InMemoryAgentProvider implements AgentProvider {
  InMemoryAgentProvider({required this.scripts});

  final List<TurnScript> scripts;
  int _turnIndex = 0;

  @override
  Stream<AgentEvent> turn({...}) async* {
    final script = scripts[_turnIndex++];
    for (final event in script.events) {
      if (event.delayMs > 0) await Future.delayed(Duration(milliseconds: event.delayMs));
      yield event.event;
    }
  }

  @override
  Future<bool> validateKey(String key) async => key == 'fake-valid-key';

  @override
  Future<List<double>> embed(String text) async {
    // Deterministic hash → vector for golden tests
    return _deterministicEmbedding(text);
  }
}

class TurnScript {
  final List<ScriptedEvent> events;
  TurnScript(this.events);
}

class ScriptedEvent {
  final AgentEvent event;
  final int delayMs;
  ScriptedEvent(this.event, {this.delayMs = 0});
}
```

**Why scripts not record/replay:** Real provider traces are noisy, version-dependent, and contain conversation content we don't want in fixtures. Scripts are explicit, hand-authored, and version-controlled. Each test reads like a story:

```dart
final provider = InMemoryAgentProvider(scripts: [
  TurnScript([
    ScriptedEvent(TextDelta('Looking at the page...')),
    ScriptedEvent(ToolCall('read_page', {'scope': 'viewport'}, id: 'tc_1')),
    ScriptedEvent(TurnEnd(TurnEndReason.toolCalls, TurnUsage(inputTokens: 1200, outputTokens: 80))),
  ]),
  TurnScript([
    ScriptedEvent(TextDelta('Found a search box. Typing your query.')),
    ScriptedEvent(ToolCall('fill', {'id': 'h:8c91', 'value': 'AAPL'}, id: 'tc_2')),
    ScriptedEvent(ToolCall('click', {'id': 'h:a3f2'}, id: 'tc_3')),
    ScriptedEvent(TurnEnd(TurnEndReason.toolCalls, TurnUsage(inputTokens: 1400, outputTokens: 60))),
  ]),
]);
```

The agent loop runs against this exactly as it would against Anthropic. Tests assert on which tools the executor was asked to run, in what order, with what args.

---

## 3. Real provider tests

Two parallel provider abstractions need provider tests: `AgentProvider` (main agent) and `EdgeDefenseProvider` (defense ops).

### 3.1 Cloud `AgentProvider` golden tests

We do not hit live APIs in CI. Each real provider (Anthropic, OpenAI, Google) has its own golden test suite at `test/ai/providers/<name>/`:

- `fixtures/` — captured raw HTTP response payloads (real but **scrubbed**: no real keys, generic prompts, no PII)
- `<name>_test.dart` — feeds the fixtures into the provider's adapter, asserts on the resulting `Stream<AgentEvent>`

Capture process when adding a new fixture:

1. Run the provider against a curated test prompt locally with `tool/capture_fixture.dart`
2. The script scrubs auth headers, scrubs identifying content, writes the raw response body to `fixtures/`
3. Commit the fixture and add a corresponding test case

Update process when a provider changes its API: re-capture fixtures, run the suite, fix the adapter until it passes. The fixtures are the canonical contract.

### 3.2 Live tests as a separate suite

`test_live/` is not run by default, not in CI, and requires an env var. Used pre-release to confirm the adapters still work against real APIs. Every release runs the live suite manually before tagging.

### 3.3 `CloudFallbackEdgeProvider` tests

Same pattern as cloud `AgentProvider` golden tests but at `test/ai/edge/cloud_fallback/`. Captured fixtures of the cheap-tier model's responses to canonical defense-op inputs (paraphrase, classify, reflect, summarize). Asserts on the parsed `ClassifierVerdict` / `ReflectionVerdict` / `ParaphraseResult` objects, not raw response bodies.

### 3.4 `AICoreEdgeProvider` tests (Android Gemini Nano)

Edge providers need their own test surface because the model lives on-device.

**Kotlin-side unit tests** (`android/app/src/test/`):
- `AICoreClient` mock-based tests for serialization, error mapping, quota handling
- `CapabilityDetector` tests for tier classification across Android versions
- `QuotaTracker` tests for daily-cap enforcement and reset behavior

**Dart-side platform-channel tests:**
- `aicore_edge_provider_test.dart` mocks the platform channel and asserts the Dart side correctly serializes requests, deserializes responses, and propagates errors as typed `ProviderError` objects.

**Captured-fixture tests against real Gemini Nano output:**
- Run a one-off harness (`tool/capture_nano_fixtures.dart`) on a Tier A device against canonical defense-op inputs.
- Captured outputs go into `test/ai/edge/aicore/fixtures/` as JSON.
- The Dart-side test feeds the same canonical inputs through `InMemoryEdgeProvider` configured with the captured fixtures, asserting downstream defense-pipeline behavior matches.
- Re-capture when Gemini Nano version drifts (Nano 3 → Nano 4, etc.); the fixtures are the contract for "what the edge model returns on this input."

**Instrumented integration tests** (real device, manual or Firebase Test Lab):
- `test_android/edge_defense_integration_test.dart` runs the actual `AICoreEdgeProvider` against a live AICore on a Pixel 8+ emulator or physical device.
- Smoke-level: each defense op returns a non-error result on a known-good input.
- Quota probe: hammer the API to verify graceful `ErrorCode.BUSY` handling and exponential backoff.
- Not run on every PR (slow); required on release branches.

**Tier coverage in CI:** Firebase Test Lab matrix runs the integration suite against:
- Pixel 8 with AICore enabled (Tier A) — full edge path tested
- Pixel 7 on Android 14 (Tier B without AICore) — cloud-fallback path tested
- API 33 emulator (Tier C) — verifies the AI build manifest correctly excludes these devices, OR the cloud-only path works for Path B compatibility scenarios

### 3.5 `AppleFoundationEdgeProvider` tests (v3.x)

Same pattern as `AICoreEdgeProvider` adapted to Swift / iOS:
- Swift-side unit tests for the Foundation Models wrapper
- Dart-side platform-channel tests
- Captured fixtures from real Apple Foundation Models output
- XCTest integration tests in CI on a Mac runner

Lands with iOS support in v3.x.

---

## 4. Unit tests

Anything pure logic. High coverage expected (see §10).

**Required unit-test coverage for v1:**

- `navigation_policy.dart` — wildcard matching, public-suffix matching, blocked-scheme rejection, edge cases (`evil-flutter.dev.attacker.com` does not match `flutter.dev`, `*.example.com` doesn't match `example.com`, etc.)
- `memory_router.dart` — heuristic classification (every regex / keyword case), confidence thresholds, escalation triggers
- `episodic_memory.dart` — FTS5 query construction, host filter, recency boost, retention
- `semantic_memory.dart` — vector similarity ranking, fallback to keyword
- `auto_extractor.dart` — extraction prompt → fact list (golden tests against fake provider)
- `cost_tracker.dart` — soft/hard limit triggering, step threshold, monthly accumulation
- `autonomy.dart` — for each (action_class, host_trust_level) pair, asserting confirm vs. auto vs. always-confirm
- `redaction.dart` — every sensitive field name produces redacted output; field-name matching is case-insensitive
- `ai_config.dart` — every YAML schema variant, validation errors for mismatched preset combos, defaults for missing keys
- `page_reader.dart` (Dart side) — DOM digest deserialization, hash-stable id reconstruction
- `set_of_marks.dart` — number → element id mapping survives mutation
- **`task_classifier.dart`** — heuristic classification across (tool count, prompt length, skill metadata, destructive-action presence) producing (`routine` | `reasoning` | `heavy`) verdicts with reproducible rule traces
- **`model_router.dart`** — for each (preset × class × provider × override) combination, the right model is picked; cross-provider overrides honored; local-only mode routes everything to `LocalEdgeAgentProvider` regardless of preset (v2 prep)
- **`routing_policy.dart`** — preset definitions enforced, override constraints enforced, badge-display logic
- **`credential_store.dart`** — `byok_keys` mode round-trips cleanly; `managed_session_token` mode stub returns expected "not yet supported" errors in v1; correct credential is loaded based on `ai.billing.mode`
- **`billing_mode.dart`** — mode resolution from YAML, runtime mode switching guards, rejection of unsupported modes per release
- **`capability_detector.dart`** (cross-platform Dart wrapper) — Tier A / B / C classification logic, A+ classification logic, fallback when AICore is downloading or unavailable
- **`site_profile_registry.dart`** — host lookup, default fallback, wildcard host matching for profile selection (multi-host-ready in v1 even though only one entry)
- **`system_prompt_composer.dart`** — composition from base + profile + user prefs produces correct concatenation; missing profile uses default; per-host preference overrides correctly applied
- **Reading toolkit tests** (`save_article`, `summarize_section`, `follow_citations`, `extract_claims`, `build_topic_map`, `compare_articles`, `find_contradictions`) — each tool's pure-logic surface (input validation, structured output shape, error paths) tested against fake provider responses; integration paths covered by widget tests

---

## 5. JS-side tests

`assets/ai_agent.js` is JavaScript and needs its own test surface. We test it two ways:

**Unit-level (Node, jsdom):** `test_js/` runs Jest against a jsdom DOM. Asserts on:

- DOM digest output for canned HTML inputs
- Hash-stable element id derivation (same DOM → same ids; mutated DOM → predictable id changes)
- Set-of-Marks overlay injection / removal cycle
- Click and fill helpers find the right element by id
- **Sanitization pipeline (§4.5 of `AI_DESIGN.md`):** hidden elements stripped, comments removed, aria-label injection patterns rejected, off-screen elements not in digest

Run via `npm --prefix test_js test`. CI runs this as a parallel job.

**Integration with WebView:** Covered by widget-test-level harness that loads a real `WebView` against `assets:///test_pages/*.html` fixtures. Slower; fewer cases. Catches timing and serialization bugs the jsdom level can't.

---

## 6. Adversarial security test fixtures

The defense pipeline is only as good as the tests that verify it. Each scenario from `AI_THREAT_MODEL.md` §5 has a fixture in `test/ai/security/`. The fixtures are versioned, never auto-regenerated.

**Fixture format.** Each scenario is a directory:

```
test/ai/security/scenario_01_html_comment_injection/
  page.html              — the hostile page (HTML fixture)
  task.json              — user task definition: {prompt, host, expected_action}
  expected_behavior.md   — narrative description: what should happen, why
  scripts/
    edge_classifier.json — captured Gemini Nano verdict on this input
    edge_reflection.json — captured Gemini Nano reflection on the proposed action
    cloud_classifier.json — fixture for cloud-fallback path
    cloud_reflection.json
  asserts.dart           — Dart test asserts
```

**Per-scenario test runs:**

1. Load `page.html` into a test WebView (or jsdom for JS-only assertions).
2. Run the DOM digest with sanitization (§4.5) — assert hidden / injected content is stripped.
3. Run spotlighting wrapper — assert `<untrusted_content>` markers are correct.
4. Feed sanitized digest into `InMemoryEdgeProvider` configured with the captured edge classifier verdict — assert classifier downstream effects (host trust, autonomy escalation).
5. Run the agent loop with `InMemoryAgentProvider` returning the agent's plausible (canned) response — assert the proposed action.
6. Run flow-check (§9.5) — assert sink rule outcome (allowed / confirm / blocked).
7. Run self-reflection (§9.6) with `InMemoryEdgeProvider` returning the captured reflection verdict — assert escalation behavior.
8. Assert audit log contains full provenance trail.

**v1 minimum scenario count: 25.** Listed in `AI_THREAT_MODEL.md` §5 (12 sample scenarios listed; full set lives in `test/ai/security/manifest.yaml`).

**CI gate:** all security scenarios pass on every PR. Failure to defend against a known scenario blocks the PR. New scenarios added when:
- A competitor product is publicly exploited and the technique applies to us
- A new attack class appears in the literature
- A user reports an issue that turns out to be in scope

**Pre-release red-team drill:** Before each release, the security suite runs against the candidate build. Plus a manual review cycle where the security team (or, in early days, the lead developer) attempts to construct novel attacks against the build. Failures get captured as new fixtures.

**Adversarial test fixtures are not auto-generated.** Each is hand-authored. Auto-generation produces shallow fixtures that pass shallow defenses; the value is in the human-curated examples that look plausible but exercise specific sub-types.

---

## 7. Widget tests

For every UI surface in `lib/ai_ui/`:

- `floating_dock_test.dart` — dragging, edge-snapping, hide gesture, tap-to-expand
- `chat_panel_test.dart` — message rendering, tool trace expansion/collapse, snap points, dismiss gestures, **per-turn routing badge displays correct tier × model × cost**
- `confirm_sheet_test.dart` — renders proposed action, redacts sensitive values, Yes/No callbacks, surfaces self-reflection result when `INCONSISTENT`
- `byok_setup_test.dart` — provider picker, validation success/failure flows, redacted display after save, security_posture string surfaced from `provider_meta.dart`
- `mode_picker_test.dart` — three-mode UI shown to Tier A+ devices; managed grayed out in v1 with "coming soon" label; local grayed out pre-v2 with "coming in v2" label; Tier B/C devices see two options (BYOK + grayed managed); branch wiring test confirms only BYOK path is reachable in v1
- `routing_settings_test.dart` — preset picker (cost-conscious / balanced / quality-first), per-class override controls, cross-provider override warning when user lacks the key
- `home_url_picker_test.dart` (browser preset only, v2) — preset selection, custom URL validation, PSL auto-suggest, save to `preference_store`
- `ai_settings_test.dart` — every section renders, every action button wired, "delete all agent data" cascades correctly
- `memory_page_test.dart` — categorized rendering, per-row delete, export, "review pending facts" flow
- `audit_log_page_test.dart` — chronological rendering, search, export, full provenance trail expansion
- `billing_page_test.dart` — BYOK-mode UI in v1 (key list + add/remove); managed-mode UI placeholder (visible label "managed coming in v1.5"); local-mode UI placeholder ("local coming in v2 for capable devices")

Use `Provider`-injected fakes for everything below the widget under test. No real network, no real DB, no real key store.

---

## 8. Integration tests

Small in count. Each exercises a complete, realistic task end-to-end with the fake provider, real memory layers (in-memory sqflite via `sqflite_common_ffi`), and real navigation policy.

Required integration tests for v1:

1. **Cold start → BYOK setup → first agent task → episodic memory persists.**
2. **Agent navigates within allowlist → succeeds; agent navigates outside allowlist → blocked, audited, model receives `E_ORIGIN`.**
3. **Destructive action triggers confirm sheet → user denies → agent recovers and reports back; user approves → executes.**
4. **Auto-extraction queues facts → Memory page shows pending review → user approves one, edits one, rejects one → semantic memory state matches.**
5. **Token budget soft limit → "continue?" prompt → user confirms; hard limit → auto-terminate with budget-exhausted message.**
6. **Memory router heuristic → episodic recency boost → relevant prior turn surfaces in next task.**
7. **"Delete all agent data" → every category empty, key store untouched, audit log shows the wipe.**
8. **Provider switch → old key remains in store, new provider validates, new turns use new provider, embeddings provider migrates if needed.**
9. **Wikipedia spearhead end-to-end** — load a canned Wikipedia article fixture, run a full reading-toolkit task ("summarize this article and follow its citations"), assert: profile loaded from registry, system prompt composed correctly, sanitization stripped vandalism-style hidden text, classifier verdict was `low`, save_article persists to resource memory, audit log shows full provenance chain.
10. **Task-class routing end-to-end** — user with `balanced` preset issues a routine query (page summary), verify `routine`-tier model picked; same user issues a heavy query (build topic map across 5 articles), verify `heavy`-tier model picked; routing badges displayed correctly in chat panel; cost tracker accumulates per-class spend.
11. **Defense pipeline end-to-end on Wikipedia-shaped fixture** — sanitization → classifier (edge first, cloud fallback if `InMemoryEdgeProvider` says unavailable) → spotlighting → main agent → flow-check → self-reflection → confirm-sheet on destructive action.
12. **Site-profile bundle** (Wikipedia, the only entry in v1) — agent loads profile when navigating to `*.wikipedia.org`; multi-host architecture ready (registry returns the one entry; default fallback path tested even though unused in v1).

Required integration tests added in subsequent releases:

- **v1.x:** Stack Overflow profile loading + SO-specific tools; site-profile registry with two entries; bundle format validation.
- **v1.5:** Managed-mode end-to-end with mock proxy server (registers account → buys credits → runs task → credits decremented); BYOK-to-managed mode-switch flow.
- **v1.y:** Reddit profile loading; defense layer's classifier hit-rate against Reddit-shaped adversarial fixtures.
- **v2:** Local-only mode end-to-end on simulated Tier A+ device (using `InMemoryEdgeProvider` returning Nano-shaped responses); first-visit profile generation; skill-learning review UX.

These are slow (seconds each). Worth it. They catch the integration bugs that pyramid-level testing misses.

---

## 9. What we don't test (deliberately)

- **Real provider response content.** We test that the adapter parses a fixture correctly, not that Claude / GPT / Gemini happen to return any specific text for any specific prompt. Tests against generated content are flaky and pointless.
- **Agent quality.** "Did the agent successfully book the flight" is a benchmark concern, not a unit-test concern. We track agent quality through dogfooding and structured eval suites (`eval/`), not pytest-style assertions.
- **Real network.** No outbound HTTP from CI. Ever. Use fixtures.
- **Real keystore.** `flutter_secure_storage` has its own tests; we wrap it behind `SecretStore` and inject a fake in tests.
- **Real WebView page loading.** Too slow, too flaky, too platform-dependent. WebView tests use canned local HTML in widget-test mode.

---

## 10. Coverage targets and CI gates

**v1 minimum coverage thresholds (enforced in CI):**

- `lib/ai/`: 85% line coverage
- `lib/ai/providers/`: 80% line coverage (real-provider adapters; some untestable branches around live network errors)
- `lib/ai/memory/`: 90% line coverage (it's the safety surface)
- `lib/ai_ui/`: 70% line coverage (widget tests are inherently lower-density)
- `lib/config/ai_config.dart`: 95% (parsing must be airtight)

CI runs:

1. `dart format --set-exit-if-changed .` (fail on unformatted code)
2. `flutter analyze` (zero warnings)
3. `flutter test --coverage`
4. `lcov --list coverage/lcov.info` against thresholds
5. `npm --prefix test_js test`
6. Debug Android build (catches Gradle / manifest regressions)
7. (Optional, runs on labeled PRs) integration test suite

Failing any gate blocks merge. No exceptions for "I'll fix it in the next PR."

---

## 11. Test data hygiene

- **No real PII in fixtures, ever.** Synthetic emails (`test@example.com`), synthetic names, synthetic conversations. Even when capturing from a real provider response, scrub before commit.
- **Fixture comments document scope.** Every fixture file has a header: what prompt produced it, what the test is asserting, when it was last refreshed.
- **Fixtures get refreshed yearly or on adapter changes,** whichever comes first. Stale fixtures hide adapter drift.
- **Snapshot tests use deterministic input.** No `DateTime.now()`, no `Random()` without a seed, no platform-dependent values. The fake provider's deterministic embedding helper is part of this discipline.

---

## 12. Pre-commit / pre-push

Recommend (not enforced) a pre-commit hook running `dart format` and `flutter analyze`. Documented in `CONTRIBUTING.md` (to be added in a later PR). The CI gates are the actual enforcement; the local hooks are for fast feedback.

---

## 13. The eval suite (separate concern)

Quality testing — "is the agent good at its job" — lives in `eval/`, runs separately from `test/`, and uses real providers. Out of scope for v1 unit/widget/integration tests but worth flagging now so the directory exists from the start.

`eval/` contents (v1.x onward):

- Curated task prompts ("find the cheapest hotel in Tokyo for next weekend")
- Site fixtures for repeatable evaluation
- Pass/fail criteria (did the agent reach the right page? did it confirm before submitting? did it stay within budget?)
- Run with `dart run eval/run.dart --provider anthropic --site hn` etc.

This is not part of CI. It's a deliberate, occasional, human-reviewed run before each release.
