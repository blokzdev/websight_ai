# WebSight-AI: Edge Defense Layer

Written before agent-runtime code lands so the edge offload is foundational, not retrofitted.

**Read alongside:** [`AI_THREAT_MODEL.md`](AI_THREAT_MODEL.md) for what we're defending against and the layered defense architecture; [`AI_DESIGN.md`](AI_DESIGN.md) §4 (page reading), §9 (trust & safety), and §17 (this doc's home in the architecture); [`AI_SPEC.md`](../AI_SPEC.md) for v1 scope.

This document is the canonical reference for how WebSight-AI runs defense-layer compute on the user's device wherever possible, with cloud fallback for unsupported devices and operations that genuinely require frontier reasoning.

---

## 1. Why edge

The defense layers in `AI_THREAT_MODEL.md` §4 — sanitization, spotlighting, classification, paraphrasing, self-reflection — are mostly small, focused operations that don't require frontier reasoning. They are also the operations that scale linearly with browsing activity (one classifier call per page read, one paraphrase per high-risk page, one reflection per destructive action). Running them all in the cloud means:

- **Multiplied BYOK cost.** Defense calls compound on top of the agent calls the user is paying for. Naive cloud-only defenses are 10–40× the agent-call cost across a typical session.
- **Page content leaves the device for the defense layer.** Even if the agent ultimately doesn't need to send a particular page to the cloud, defense classification does.
- **Latency stacks.** Each defense layer adds one network round-trip. Five defense layers add a noticeable beat to every page read.
- **Defenses fail when the network does.** A sanitization layer that requires a cloud call breaks the offline story.

Running defenses on-device flips all four:

- **Zero marginal cost.** On-device inference uses the user's processor, no API charges. Per Yassine Beldi's writeup of the standard pattern, *"Aside from app size or initial setup, inference is handled by the user's processor, meaning zero server inference costs."*
- **Page content never leaves the device for the defense layer.** Classification, paraphrase, and first-pass reflection all happen locally. Only the final agent call (which the user already pays for via BYOK) sends data to the cloud, and that data has already been sanitized and laundered through the edge layer.
- **Sub-100ms latency for most defense ops.** No network round-trip.
- **Defenses work offline.** The agent loop itself requires network for the BYOK provider, but defenses don't gate on it.

The platform reality also reached the right place at the right time. Google's Gemini Nano is on 140M+ Android devices via AICore as of 2026. Apple Foundation Models is on most iOS 18+ devices. ML Kit GenAI APIs and AI Edge SDK provide clean Android-native surfaces. Apple Intelligence's Foundation Models framework provides the iOS equivalent. We do not bundle models — the OS distributes and updates them, we just call.

This makes edge offload not a "v2 nice-to-have" but the **architecturally correct primary path** for several defense layers in v1, with cloud fallback as an explicit second tier rather than the default.

---

## 2. Platform capabilities (May 2026 baseline)

What we can actually rely on, by platform.

### 2.1 Android (v1 primary platform)

**Gemini Nano via AICore.** Available on Pixel 8+, Galaxy S24+, Pixel 10, Galaxy S26, and an expanding set of flagship devices. AICore handles model distribution, version management, and hardware acceleration (Google Tensor, MediaTek, Qualcomm NPUs). We integrate via:

- **ML Kit GenAI APIs** — high-level wrappers for summarization, rewriting, proofreading, image description, prompt-based generation. `com.google.mlkit:genai-summarization`, `genai-rewriting`, `genai-prompt`. Recommended primary surface for our use cases.
- **AI Edge SDK** — lower-level. `com.google.ai.edge.aicore:aicore`. Direct prompt API with parameter control (temperature, top-k, top-p). Use when ML Kit's high-level APIs don't fit.

Capability tiers we actively support:

| Tier | Devices | What works |
|---|---|---|
| A+ — High-end AICore w/ TPU acceleration | Pixel 10+, Galaxy S26+, equivalent flagships with Gemini Nano 3+ (~50–100M devices, growing) | Full edge defense layer **plus** v2 local-only agent reasoning (`LocalEdgeAgentProvider`). Hardware sufficient for sustained multi-step tool-calling agentic loops. |
| A — AICore-enabled | Pixel 8+, Galaxy S24+, recent flagships from Motorola, Xiaomi, etc. (~140M+ devices, includes A+ subset) | Full edge defense layer: classifier, paraphrase, summarize, rewrite, first-pass reflection. v2 local-only mode is *not offered* (insufficient hardware for sustained agent loops). |
| B — Android 14+ but no AICore | Mid-tier devices on API 34+ without AICore module | Edge sanitization and spotlighting (deterministic). Cloud fallback for classifier/paraphrase/reflect. v2 local-only mode unavailable. |
| C — Below Android 14 | Older devices, API < 34 | AI build cannot install (Path A floor). User stays on plain WebSight or upgrades device. |

The A vs A+ distinction is critical for v2 local-only mode. Tier A is sufficient for *short, structured* defense ops (classify, paraphrase, reflect — tens to hundreds of milliseconds of inference). Tier A+ adds the headroom for *sustained agent reasoning* across multi-turn loops with tool calling, structured output, and longer contexts. The same `AICoreClient.kt` underlies both — the difference is what we trust the hardware to do reliably without thermal throttling or context overflow.

Min Android API for the AI build is API 34 (Android 14) — see §9 below for upgrade rationale.

**Gemini Nano version handling.** Multiple Nano versions exist concurrently (Nano 1, Nano 2, Nano 3 on Pixel 10 / Galaxy S26, Nano 4 in preview). AICore automatically provisions the right version for the device's hardware. Our code is version-agnostic — we call ML Kit GenAI APIs and trust AICore to route. We do version-tolerance testing across the matrix.

**Foreground-only constraint.** AICore returns `BACKGROUND_USE_BLOCKED` if the app is not the top foreground app. This is fine for our use case (the user is actively browsing) but means we cannot run defenses against background tabs, push-triggered ops, or scheduled work.

**Per-app inference quotas.** AICore enforces rate limits and a daily battery-use budget. Violations return `ErrorCode.BUSY` (rate limit, retry with backoff) or `ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED` (daily cap, must fall back to cloud or skip optional defenses for the rest of the day). Our `EdgeDefenseProvider` implementation tracks remaining quota and falls back gracefully.

### 2.2 iOS (v3.x)

**Apple Foundation Models framework.** Released 2025 alongside Apple Intelligence. ~3B-parameter on-device LM, available on iOS 18+ devices with sufficient hardware (A17 Pro, A18, M-series). Native Swift API; we bridge via Flutter platform channels.

iOS posture is staged for v3.x — see `AI_DESIGN.md` §16. The `EdgeDefenseProvider` interface is platform-agnostic from v1 so the iOS implementation lands cleanly when iOS broadly does. Through v1 → v2, WebSight-AI is Android-only.

### 2.3 Devices without on-device AI

Cloud fallback. The `EdgeDefenseProvider` interface is the same; the implementation routes to a cheap-tier cloud model (Haiku, GPT-5-Nano, Gemini Flash) using the user's BYOK key. Cost is non-zero but bounded by the cheap-tier model's pricing.

---

## 3. The `EdgeDefenseProvider` abstraction

Lives in `lib/ai/edge/`. Parallel structure to `lib/ai/providers/` for the main agent provider — same separation-of-concerns logic, different surface.

```dart
// lib/ai/edge/edge_defense_provider.dart

abstract class EdgeDefenseProvider {
  /// Whether this provider is available on the current device right now.
  /// Checked at agent-loop construction; may return false if quota exhausted.
  Future<bool> isAvailable();

  /// Paraphrase untrusted page content. Returns text that preserves meaning
  /// but breaks exact-match adversarial triggers via token reshuffling.
  /// Should not be used for high-fidelity tasks (form-filling).
  Future<ParaphraseResult> paraphrase(String text, {ParaphraseHint? hint});

  /// Classify whether content contains likely indirect prompt injection.
  /// Binary verdict + flags + matched pattern. Cheap; first defense gate.
  Future<ClassifierVerdict> classifyInjection(String text);

  /// First-pass self-reflection: is the proposed action consistent with the
  /// user's request, given the untrusted content visible in recent context?
  /// Returns CONSISTENT / INCONSISTENT / UNCERTAIN.
  /// UNCERTAIN escalates to cloud reflection.
  Future<ReflectionVerdict> reflectAction({
    required String userIntent,
    required ProposedAction action,
    required String contextDigestSummary,
  });

  /// Summarize page content into a concise digest.
  /// Used for hot-context summarization and audit log entries.
  Future<String> summarize(String text, {int? maxTokens});
}

enum RiskLevel { low, elevated, high }

class ClassifierVerdict {
  final RiskLevel risk;
  final List<String> flags;
  final String? matchedPattern;
  final Duration latency;

  const ClassifierVerdict({
    required this.risk,
    required this.flags,
    this.matchedPattern,
    required this.latency,
  });
}

enum ReflectionResult { consistent, inconsistent, uncertain }

class ReflectionVerdict {
  final ReflectionResult result;
  final String reason;             // surfaced to user in confirm sheet
  final double confidence;         // 0.0–1.0; used to decide cloud escalation
  final Duration latency;

  const ReflectionVerdict({
    required this.result,
    required this.reason,
    required this.confidence,
    required this.latency,
  });
}

class ParaphraseResult {
  final String text;
  final double semanticPreservation; // heuristic; not for security claims
  final Duration latency;

  const ParaphraseResult({
    required this.text,
    required this.semanticPreservation,
    required this.latency,
  });
}
```

Three concrete implementations land in v1:

- `AICoreEdgeProvider` — Android Gemini Nano via ML Kit GenAI. Primary path on supported devices.
- `CloudFallbackEdgeProvider` — uses a cheap-tier cloud model via the user's BYOK key. Fallback on unsupported devices.
- `InMemoryEdgeProvider` — fake for tests. Returns deterministic results based on a `TurnScript` analogous to `InMemoryAgentProvider`. See `AI_TEST_STRATEGY.md` §3.

`AppleFoundationEdgeProvider` lands in v3.x with iOS support.

---

## 4. The `DefenseCoordinator`

Lives in `lib/ai/edge/defense_coordinator.dart`. Picks which provider runs each operation per call. Responsibilities:

1. **Capability detection at construction.** Probes platform, device, AICore availability. Caches.
2. **Per-operation routing.** Some operations (paraphrasing) are edge-strong; some (high-stakes self-reflection) require cloud escalation. The coordinator encodes the rules.
3. **Quota-aware fallback.** Tracks AICore quota usage. Auto-falls-back to cloud when the daily cap is approached.
4. **User-pref override.** Users can force `edge_only`, `cloud_only`, or `auto` (default) in AI Settings.
5. **Telemetry** (local-only, opt-in). Counts of edge vs cloud routing per op, fallback reasons. For diagnostics, never sent off-device unless user explicitly exports.

Routing rules in the auto path:

| Operation | Edge-preferred? | Escalation rule |
|---|---|---|
| Sanitization (deterministic) | Always edge — JS/Dart, no model | (no escalation; runs everywhere) |
| Spotlighting wrap (deterministic) | Always edge — string manipulation | (no escalation) |
| Retrieved-data classifier | Yes | Edge unless unavailable; no cloud escalation on `low`/`high`. On `elevated` with low confidence, optionally cross-check with cloud. |
| Paraphrasing | Yes | Edge unless unavailable. Quality probe (length, repetition) at edge — if output looks degraded, retry once at cloud. |
| First-pass self-reflection | Yes | Edge first. If verdict is `UNCERTAIN` AND action is destructive, escalate to cloud reflection. |
| Cloud second-opinion reflection | No (cloud only) | Triggered only by `UNCERTAIN` edge verdict on destructive action. |
| Summarize (hot-context, audit) | Yes | Edge always; no cloud fallback for these (best-effort; non-blocking). |

Implementation pattern:

```dart
// lib/ai/edge/defense_coordinator.dart

class DefenseCoordinator {
  final EdgeDefenseProvider _edge;
  final EdgeDefenseProvider _cloudFallback;
  final UserPreference _pref;
  final QuotaTracker _quota;

  Future<ClassifierVerdict> classifyInjection(String text) async {
    if (_pref.mode == EdgeMode.cloudOnly) {
      return _cloudFallback.classifyInjection(text);
    }
    if (_pref.mode == EdgeMode.edgeOnly) {
      return _edge.classifyInjection(text);
    }
    // auto
    if (await _edge.isAvailable() && _quota.hasRemaining(EdgeOp.classify)) {
      try {
        final v = await _edge.classifyInjection(text);
        _quota.consume(EdgeOp.classify);
        return v;
      } catch (e) {
        _logFallback('classify', reason: e);
        return _cloudFallback.classifyInjection(text);
      }
    }
    return _cloudFallback.classifyInjection(text);
  }

  Future<ReflectionVerdict> reflectAction({
    required String userIntent,
    required ProposedAction action,
    required String contextDigestSummary,
  }) async {
    final edgeVerdict = await _runEdgeOrFallback(/* ... */);
    if (edgeVerdict.result == ReflectionResult.uncertain && action.isDestructive) {
      // Escalate to cloud for second opinion
      return _cloudFallback.reflectAction(
        userIntent: userIntent,
        action: action,
        contextDigestSummary: contextDigestSummary,
      );
    }
    return edgeVerdict;
  }

  // ... similar for paraphrase, summarize
}
```

The coordinator is the only thing the agent loop calls. Provider selection is invisible above this line.

---

## 5. AICore integration on Android

Flutter cannot call ML Kit GenAI APIs directly — they're Kotlin/Java native. We use platform channels:

```
lib/ai/edge/
  edge_defense_provider.dart          # abstract interface
  aicore_edge_provider.dart           # Dart-side, calls platform channel
  cloud_fallback_edge_provider.dart   # Dart-side, uses HTTP via cheap provider
  defense_coordinator.dart
  models.dart                         # shared types
android/app/src/main/kotlin/cc/websight/app/edge/
  EdgeDefensePlugin.kt                # registers method channel
  AICoreClient.kt                     # ML Kit GenAI wrapper
  CapabilityDetector.kt               # AICore availability probe
  QuotaTracker.kt                     # mirrors Dart-side; native is source of truth
  Models.kt                           # serialization for the channel
```

The method channel name is `cc.websight.app/edge_defense`. Methods:

- `is_available` — returns `{available: bool, tier: 'A'|'B'|'C', reason: string?}`
- `classify_injection` — args `{text: string}`, returns serialized `ClassifierVerdict`
- `paraphrase` — args `{text: string, hint: string?}`, returns serialized `ParaphraseResult`
- `reflect_action` — args `{user_intent, action, context_summary}`, returns serialized `ReflectionVerdict`
- `summarize` — args `{text, max_tokens}`, returns `{summary: string, latency_ms: int}`

Capability detection (Kotlin-side):

```kotlin
fun isAICoreEnabled(): CapabilityResult {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        return CapabilityResult(false, "C", "API < 34")
    }
    val isEmulator = Build.FINGERPRINT.startsWith("generic") ||
                     Build.FINGERPRINT.startsWith("unknown")
    if (isEmulator) return CapabilityResult(false, "C", "emulator")

    // ML Kit GenAI feature availability check
    val featureStatus = GenAI.getFeatureStatus(/* relevant feature id */)
    return when (featureStatus) {
        FeatureStatus.AVAILABLE -> {
            val tier = if (isAPlusDevice()) "A+" else "A"
            CapabilityResult(true, tier, null)
        }
        FeatureStatus.DOWNLOADING -> CapabilityResult(false, "B", "downloading")
        FeatureStatus.UNAVAILABLE_DEVICE -> CapabilityResult(false, "B", "unsupported_device")
        else -> CapabilityResult(false, "B", "feature_unavailable")
    }
}

// A+ classification — used by v2 local-only mode (LocalEdgeAgentProvider).
// In v1, A+ is detected and reported but only A vs B/C affects defense routing.
private fun isAPlusDevice(): Boolean {
    // Heuristic combination: Nano version, accelerator presence, RAM, thermal headroom
    val nanoVersion = AICoreClient.getInstalledNanoVersion()
    if (nanoVersion < 3) return false
    val hasNPU = HardwareCapabilities.hasTPU() || HardwareCapabilities.hasHexagonNPU()
    if (!hasNPU) return false
    val ram = HardwareCapabilities.totalRamMb()
    return ram >= 8192  // 8GB+ RAM threshold for sustained agentic inference
}
```

Tier B (no AICore but Android 14+) is treated as "edge sanitization works, edge models don't" — the coordinator falls back to cloud for model ops.

Initialization: AICore models may need to be downloaded on first use. We handle this in `AICoreClient.warmup()`, called from app startup (post-onboarding, post-network-check) and from a manual "Initialize on-device AI" button in AI Settings. Download size is ~1GB for Gemini Nano. We display progress; we do not block the agent on this (cloud fallback covers the gap).

---

## 6. Defense layer execution map

Concrete mapping from each defense in `AI_THREAT_MODEL.md` §4 to its execution location.

| Defense | Execution | Notes |
|---|---|---|
| §4.5 Sanitization (`ai_agent.js`) | Edge always (JS in WebView) | Pure deterministic. No model. Runs on every device. |
| §4.6 Spotlighting wrapper | Edge always (Dart) | String manipulation. No model. |
| §4.7 Retrieved-data classifier | **Edge primary, cloud fallback** | Tier A: Gemini Nano binary classifier prompt. Tier B/C: cloud Haiku/equivalent. |
| §4.8 Paraphrasing | **Edge primary, cloud fallback** | Tier A: ML Kit GenAI Rewriting/Summarization API. Tier B/C: cloud cheap model. Off by default; opt-in per host. |
| §4.4 Information-flow tagging | Edge always (Dart) | Pure logic in `lib/ai/flow_tag.dart`. No model. |
| §4.4 Flow check at action layer | Edge always (Dart) | Pure logic in `lib/ai/flow_check.dart`. No model. |
| §4.9 Self-reflection (first-pass) | **Edge primary, cloud fallback** | Tier A: Gemini Nano consistency check. Tier B/C: cloud cheap model. |
| §4.9 Self-reflection (second-opinion on destructive UNCERTAIN) | **Cloud always** | Uses the same provider as the agent (Anthropic recommended). High-stakes. |
| Main agent reasoning | Cloud (BYOK) | Frontier reasoning required. Not edge-replaceable. |

The pattern is consistent: **deterministic operations run at the edge by definition; small classification/generation operations run at the edge first; only frontier reasoning escalates to cloud.**

---

## 7. Cost picture

Per-session estimate, comparing all-cloud vs edge-preferred for a typical task with 8 page reads, 1 destructive action, classifier always on, paraphrase off (default):

**All-cloud defense layer (worst case):**
- 8× classifier @ ~$0.0001 = $0.0008
- 0× paraphrase = $0.00
- 1× self-reflection @ ~$0.001 = $0.001
- **Total defense overhead: ~$0.002 per session**

**Edge-preferred defense layer (Tier A device):**
- 8× edge classifier = $0.00 (free, on-device)
- 0× paraphrase = $0.00
- 1× edge first-pass reflection = $0.00 (free)
- 0–1× cloud second-opinion reflection (only if edge says UNCERTAIN) ≈ $0.0005 expected
- **Total defense overhead: ~$0.0005 per session, often $0.00**

**Difference:** ~$0.0015 per session saved on Tier A devices. At 100 sessions/month per active user, that's ~$0.15/month saved. With paraphrase enabled (high-risk hosts), the savings scale further: paraphrase per page is ~$0.001 cloud, $0.00 edge.

The dollar amounts are small per user. The point is not the absolute savings — it's that the BYOK user pays the agent costs, and we should not be inflating their bill with defense overhead when most of it is offloadable.

---

## 8. Privacy implications

The privacy story is more important than the cost story.

In an all-cloud architecture, every page the agent reads goes to:
1. The defense classifier (cloud) — page content, full text.
2. The paraphraser if enabled (cloud) — page content, full text.
3. The agent reasoning (cloud) — page content, full text plus context.

In an edge-preferred architecture (Tier A device), every page the agent reads goes to:
1. The defense classifier (on-device) — page content, full text. Never leaves device.
2. The paraphraser if enabled (on-device) — page content, full text. Never leaves device.
3. The agent reasoning (cloud) — only the **paraphrased and sanitized digest**. Adversarial patterns stripped, instructions wrapped in `<untrusted_content>`, content optionally rewritten.

For users on Tier A devices, the cloud LLM sees a strictly cleaner surface than what the agent encountered. This is genuinely a stronger privacy posture than any agentic browser currently shipping. We document this prominently in onboarding and the privacy policy.

For Tier B/C devices (cloud fallback for defense layer), we are no worse than the competition and arguably better because the defense layer uses cheap-tier models with shorter retention policies than full agent calls.

A point worth being honest about: edge defenses are only as private as the platform makes them. Gemini Nano runs in Android's Private Compute Core principles, with the following key characteristics: Restricted Package Binding: AICore is isolated from most other packages. We trust the AICore sandbox; users who don't trust Android's privacy claims cannot get the privacy benefits. We do not claim privacy guarantees we cannot architecturally enforce.

---

## 9. Min Android API and the upgrade rationale

Current WebSight presumably supports lower Android versions (need to confirm exact floor; recommend Claude Code's first session task captures this). The AI build (Preset A) requires API 34+ (Android 14) for ML Kit GenAI APIs.

Two paths:

**Path A (recommended): AI build floors at API 34.** Cleaner implementation; edge defenses available to all AI users (Tier A or B). Tier C users (pre-Android 14) cannot install the AI build and stay on plain WebSight.

**Path B: AI build supports the same floor as WebSight.** Older devices fall through to cloud-only defenses with no edge layer. More complex coordinator logic; less consistent privacy story across the user base.

Recommendation: Path A. The AI build is a separate apk anyway (Preset A is a build-time gate); the API floor is just a manifest change. Users on devices below API 34 represent a shrinking minority and are likely also on devices that can't run on-device LMs anyway, so edge benefits would be minimal even if we shipped to them.

This is `[BLOCKS first PR]`-tagged — see `AI_SPEC.md` §6.

---

## 10. Quota and battery handling

AICore enforces two quota types:

- **Rate limit (per-call).** Returns `ErrorCode.BUSY`. We retry with exponential backoff (50ms, 200ms, 800ms). After three retries, fall through to cloud.
- **Daily battery quota (per-app).** Returns `ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED`. We disable edge inference for the rest of the calendar day, surface a one-time toast ("On-device AI quota reached for today; falling back to cloud for defense layer"), and resume next day.

Quota tracking is native-side (Kotlin) since AICore is the source of truth. The Dart-side coordinator queries via the platform channel before each call.

A user-visible quota indicator lives in AI Settings: "On-device AI usage today: 73% of daily budget." Power users on flagship devices won't hit this; light users won't notice.

Battery impact estimate: Gemini Nano 4 is up to 4x faster than the previous version and uses up to 60% less battery. Nano 1/2/3 use more. We are conservative on quota — better to fall back to cloud than to drain the user's battery for defenses.

---

## 11. iOS posture (v3.x)

The `EdgeDefenseProvider` interface is platform-agnostic. The iOS implementation lands in v3.x:

- `lib/ai/edge/apple_foundation_edge_provider.dart` — Dart side
- `ios/Runner/EdgeDefensePlugin.swift` — Swift bridge to Apple Foundation Models framework

Apple Foundation Models supports text generation, summarization, and classification on iOS 18+ devices with the required hardware (A17 Pro+, M-series). Capabilities map cleanly to our defense ops:

- `classifyInjection` → Foundation Models classification with custom prompt
- `paraphrase` → Foundation Models text rewriting
- `reflectAction` → Foundation Models prompt completion with structured output
- `summarize` → Foundation Models summarization

Pre-iOS 18 devices and iPhones below A17 Pro fall through to cloud (Tier B/C equivalent).

WebSight-AI is Android-only through v1 → v2. iOS support (with Apple Foundation Models providing both defense layer and v2-equivalent local-only mode) lands in v3.x as a focused release.

---

## 11.5 v2 local-only mode and the `LocalEdgeAgentProvider`

The edge AI infrastructure built in v1 for the defense layer powers more than defenses. v2 introduces **local-only mode** as a third billing path (alongside managed credits and BYOK; see `AI_DESIGN.md` §1.4) for users on Tier A+ devices who want fully on-device, fully private, fully free agentic browsing.

`LocalEdgeAgentProvider` (lives in `lib/ai/billing/`) implements the `AgentProvider` interface — same contract as `AnthropicProvider`, `OpenAIProvider`, etc. — but routes inference to the same `AICoreClient.kt` that backs `AICoreEdgeProvider`. The differences:

- **Prompt shape.** Defense ops are short, structured, single-prompt. Agent reasoning needs full system prompts, multi-turn history, tool-call schemas.
- **Tool calling.** Gemini Nano 4 advertises tool calling and structured output in the Prompt API per Google's April 2026 announcement. We use it. Quality on agentic-browser-shaped tasks is unproven outside demos, so we engineer defensively (graceful degradation on malformed tool calls, fallback prompt formats).
- **Capability gate.** Tier A is sufficient for defense ops; Tier A+ is required for agent reasoning. The `CapabilityDetector` exposes both classifications; v2's onboarding gates the local-only option on A+.

What this means for v1 work: **building the edge defense layer correctly in v1 is doing 80% of the work for v2's local-only mode.** The platform integration, the method channels, the Kotlin client, the capability detector, the quota tracker, the version-tolerance testing — all of it is shared. v2 adds prompt engineering, tool-call quality work, and the user-facing mode UI; it does not add new platform primitives.

The honest caveats from §14 apply doubly to local-only mode:
- Edge models are less capable than frontier models; the user is trading capability for privacy and cost.
- Battery and thermal cost is real for sustained inference; the in-product UX surfaces "this turn might benefit from cloud" prompts when local reasoning is failing.
- AICore version drift (Nano 3 vs Nano 4) affects agent quality more visibly than defense quality. Version-tolerance tests for agent prompts are part of v2's CI.

The `EdgeDefenseProvider` and `LocalEdgeAgentProvider` are deliberately separate abstractions despite sharing infrastructure. Defense and reasoning are different concerns; conflating them at the abstraction layer would create coupling that hurts when one evolves faster than the other.

---

## 12. Testing strategy

Three test surfaces; details in `AI_TEST_STRATEGY.md` §3.4.

### 12.1 Provider-level

Each `EdgeDefenseProvider` implementation has its own test suite:

- `aicore_edge_provider_test.dart` — Kotlin-side tests for `AICoreClient.kt`, plus a small Dart-side integration test using a Robolectric or instrumented test against actual AICore on a Pixel 8 emulator with AICore enabled. Captured fixtures from real Nano output against canonical inputs.
- `cloud_fallback_edge_provider_test.dart` — Dart tests against captured cloud fixtures, no live network.
- `in_memory_edge_provider_test.dart` — fake-provider unit tests using `TurnScript` analogue for defense ops.

### 12.2 Coordinator-level

- Routing logic: each combination of (op type × user pref × edge availability × quota state) tested with `InMemoryEdgeProvider` returning canned results.
- Escalation logic: destructive + UNCERTAIN edge verdict triggers cloud second-opinion; non-destructive + UNCERTAIN does not.
- Fallback logic: edge throws → cloud picks up; quota exhausted → cloud picks up.

### 12.3 Integration-level

- Adversarial test fixtures in `test/ai/security/` exercise the full edge-defense pipeline against canned hostile pages. Each scenario from `AI_THREAT_MODEL.md` §5 has both an edge-path test (using `InMemoryEdgeProvider` with realistic Nano-output fixtures) and a cloud-path test (using `InMemoryAgentProvider` results).
- Device-tier coverage in CI: Firebase Test Lab runs against a Pixel 8 (Tier A), a mid-tier Android 14 device (Tier B), and an emulator with API 33 (Tier C). The full security test suite must pass on Tier A; Tier B/C runs verify cloud-fallback behavior.

---

## 13. Open questions

Tagged consistent with `AI_SPEC.md` §6.

- `[BLOCKS first PR]` Min Android API for the AI build — Path A (API 34) recommended in §9 above. Need explicit decision before scaffolding lands.
- `[BLOCKS v1]` Default `ai.security.edge_defense.mode` — `auto` (recommended), `edge_only`, or `cloud_only`? Recommendation: `auto`. Power users / privacy-focused users can flip to `edge_only` and accept reduced reliability on UNCERTAIN destructive actions.
- `[BLOCKS v1]` AICore download UX — proactive on first launch (post-onboarding) or lazy on first edge call? Recommend lazy — most users won't notice the 1GB download because they have other apps using AICore already.
- `[BLOCKS v1]` Behavior on AICore-supported devices when AICore feature is in `DOWNLOADING` state — wait or fall through to cloud? Recommend: cloud fallback for first call, then edge once available. Don't block the user.
- `[BLOCKS v1]` Cloud-fallback model choice per provider when user's main agent provider is X. Concretely: if user's main agent is Anthropic Opus, the cloud-fallback edge ops should use Claude Haiku (same provider, same key, cheaper tier). Need to lock the per-provider mapping.
- `[BLOCKS v3.x]` iOS Apple Foundation Models implementation — v3.x scope. Lands as part of the iOS release.
- `[INFORMS]` Quota indicator UX in AI Settings — surface remaining edge budget visibly, or only on near-exhaustion? Recommend on near-exhaustion (unobtrusive).

---

## 14. Limitations and gotchas

We are honest about what edge defenses can and cannot do.

- **Edge models are less capable than frontier models.** Gemini Nano 2-3 is roughly comparable to last-generation cloud models in quality; Nano 4 closes more of the gap but still lags Opus / GPT-5 / Pro models substantially. For first-pass classification and paraphrasing this is fine. For nuanced reflection on sophisticated steered actions, the edge model may return UNCERTAIN often, leading to cloud escalation. We track escalation rate as a quality metric.
- **Device fragmentation is real.** Tier A is a meaningful slice of the Android user base but not the majority. Users on mid-tier devices fall to Tier B (cloud fallback for ML ops), which is functionally fine but loses the privacy benefit. We are explicit about this in the privacy explainer.
- **AICore version drift.** Different Nano versions can produce different outputs for the same prompt. ML Kit GenAI APIs abstract over this for the supported feature set, but our prompts may need version-specific tuning. We test against the active Nano versions in CI and adjust prompts as needed.
- **Foreground-only blocks some use cases.** We cannot run defenses against background-loaded content. For v1 this is fine — the agent is foreground-driven.
- **Battery quota means defenses can disable themselves.** A user running many tasks on a power-constrained device might exhaust the daily edge quota and fall through to cloud for the rest of the day. The user-visible behavior: defense layer still works, just costs the cheap-tier cloud model rate.
- **No platform on Linux/Windows desktop.** If we ever ship a desktop variant, edge AI options are different (llama.cpp, ONNX, vendor SDKs). Out of scope through v3.x.
- **Privacy claims depend on platform claims.** We trust AICore's sandbox and Apple Foundation Models' device-only execution. Users who don't trust those claims must use `edge_only` mode (which still uses the platform model) or `cloud_only` (which makes the privacy story worse, not better, but at least the trust target is one the user already chose).

---

## 15. References

- Google. *Gemini Nano on Android* (developer.android.com). Last updated April 2026. Authoritative reference for AICore architecture.
- Google. *ML Kit GenAI APIs* (developers.google.com/ml-kit/genai). Last updated April 2026. High-level surface for our use cases.
- Google. *Gemma 4: The new standard for local agentic intelligence on Android* (April 2026). Performance and battery improvements over prior Nano versions.
- Apple. *Foundation Models framework* (developer.apple.com). iOS 18+. v3.x reference.
- Yassine Beldi. *Supercharge Your Android App with On-Device AI* (April 2026). Documents the standard coordinator pattern for hybrid edge/cloud routing that we adopt.
- `AI_THREAT_MODEL.md` — what we defend against. The defenses listed there are the operations this layer executes.
- `AI_DESIGN.md` §17 — where this layer integrates with the agent loop architecture.
