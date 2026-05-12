# WebSight-AI: Conventions

Code style, file structure, naming, and process conventions. Most of these are inherited from WebSight as implicit conventions; this document makes them explicit so they don't get rediscovered by trial and error.

When a convention here conflicts with `analysis_options.yaml` or the existing WebSight code, the existing code wins — file an issue and we'll align this doc.

---

## 1. File and directory naming

- **Dart files: `snake_case.dart`.** `webview_controller.dart`, `agent_loop.dart`, `memory_router.dart`. No camelCase, no kebab-case.
- **Asset files: `snake_case`** matching their Dart counterparts. `ai_agent.js`, not `aiAgent.js`.
- **Directories: `snake_case`.** `lib/ai/memory/`, `lib/ai_ui/onboarding/`.
- **Test files mirror lib structure exactly.** `lib/ai/memory/memory_router.dart` → `test/ai/memory/memory_router_test.dart`. Same parent directory, `_test.dart` suffix.
- **Top-level packages.** Feature directories under `lib/<feature>/` for logic; `lib/<feature>_ui/` if UI is substantial enough to warrant separation. We've already established this with `lib/ai/` and `lib/ai_ui/`.

---

## 2. Type and identifier naming

- **Types (classes, enums, mixins, typedefs): `PascalCase`.** `AgentLoop`, `MemoryRouter`, `RetrievedMemory`, `AgentEvent`.
- **Methods, fields, parameters, locals: `camelCase`.** `retrieveFromEpisodic`, `currentHost`, `userTask`.
- **Constants: `lowerCamelCase`** at the top level (Dart convention since 2.0). `const maxStepsPerTask = 30;`. **Not** `MAX_STEPS_PER_TASK`.
- **Private members: leading underscore.** `_secretStore`, `_dispatch()`. Truly private to the library; not just implementation detail.
- **Stable error codes: `UPPER_SNAKE_CASE` string literals**, declared as `static const String` on a holder class. Match WebSight's existing pattern:

    ```dart
    class AgentErrorCodes {
      static const String budgetExhausted = 'E_BUDGET_EXHAUSTED';
      static const String providerError = 'E_PROVIDER';
      static const String confirmationDenied = 'E_CONFIRM_DENIED';
    }
    ```

- **Enum values: `lowerCamelCase`.** `enum AutonomyClass { auto, confirm, alwaysConfirm }`.

---

## 3. State management

WebSight uses `provider` (the package) for dependency injection and `ChangeNotifier` for view-model state. Continue this pattern; do not introduce Riverpod, Bloc, GetX, or any other state management library in v1.

- **Inject configuration and shared services with `Provider<T>` / `Provider<T>.value`.** Read at the top of `build` with `context.watch<T>()` (rebuilds on change) or `context.read<T>()` (one-shot read).
- **Use `ChangeNotifier` for any object that exposes mutable state to widgets.** Examples in WebSight: `WebsightWebViewController`, `BillingController`, `FcmController`. Match this shape — a constructor that takes config, internal mutable fields, getters, methods that mutate + call `notifyListeners()`, a `dispose()` override that flips a `_disposed` guard before super.dispose.

- **Defensive `_disposed` guard pattern.** WebSight uses this to avoid `notifyListeners()` after `dispose()` in async callbacks. Mirror it in any controller that has streams or futures:

    ```dart
    class FooController extends ChangeNotifier {
      bool _disposed = false;

      Future<void> doThing() async {
        final result = await _someAsync();
        if (_disposed) return;
        _value = result;
        notifyListeners();
      }

      @override
      void dispose() {
        _disposed = true;
        super.dispose();
      }
    }
    ```

- **No global singletons.** Inject everything through Provider. Tests need to swap implementations.

---

## 4. Error handling

- **Stable error codes for cross-layer errors.** Mirror `BridgeErrorCodes` in `js_bridge.dart`. Each layer that can fail in user-visible ways defines its own holder class. Use the codes consistently in error payloads, audit logs, and user-facing messages.
- **Exceptions for programmer errors only.** `ArgumentError`, `StateError` for "this shouldn't happen if the caller did their job."
- **`Result`-style returns for expected failures.** Tools return either a value or a structured error:

    ```dart
    sealed class ToolResult<T> {}
    class ToolOk<T> extends ToolResult<T> { final T value; ToolOk(this.value); }
    class ToolError<T> extends ToolResult<T> {
      final String code;
      final String message;
      ToolError(this.code, this.message);
    }
    ```

- **Don't swallow errors silently.** If you catch an exception, either re-throw a typed error, log it, or surface it. `try { ... } catch (_) {}` is a code-review fail unless paired with a comment explaining why silence is correct.
- **Debug prints are fine in dev, gated by `kDebugMode`.** Match WebSight: `if (kDebugMode) debugPrint('...')`. No `print()` in production code paths.

---

## 4.5 Provider abstractions

WebSight-AI has two parallel provider abstractions; both follow the same conventions.

- **`AgentProvider`** (`lib/ai/providers/agent_provider.dart`) — main agent reasoning. Implementations: `AnthropicProvider`, `OpenAIProvider`, `GoogleProvider`, `InMemoryAgentProvider` (test fake).
- **`EdgeDefenseProvider`** (`lib/ai/edge/edge_defense_provider.dart`) — defense-layer ops (paraphrase, classify, reflect, summarize). Implementations: `AICoreEdgeProvider` (Android Gemini Nano), `CloudFallbackEdgeProvider` (cheap cloud model via BYOK), `AppleFoundationEdgeProvider` (iOS, v3.x), `InMemoryEdgeProvider` (test fake).

Conventions for both:
- **Stream events, don't return blobs.** Return `Stream<AgentEvent>` / `Stream<EdgeEvent>` for any operation that can be incremental. Callers can collect or process inline.
- **Same constructor shape across implementations.** All take `({required String apiKey, required String model, ...})` — never positional args. Makes provider swapping a one-line change in tests and config.
- **Capability flags, not feature detection.** Each implementation exposes `bool get supportsX`, e.g. `supportsToolUse`, `supportsImages`, `supportsStructuredOutput`. Callers branch on the flag, not on the runtime class.
- **Errors as typed objects, never as strings.** `ProviderError(code, message, retryable)`, never raw exceptions across the layer boundary.
- **Test fakes are first-class.** `InMemoryAgentProvider` and `InMemoryEdgeProvider` live alongside production implementations; they are not buried in `test/`. They drive every higher-level test (agent loop tests, defense pipeline tests, integration tests) and stay in sync with the interface as it evolves.
- **Routing is the coordinator's job, not the provider's.** Providers don't know whether they're "primary" or "fallback." `DefenseCoordinator` (and the analogous LLM router for `AgentProvider`) handles all routing decisions. Providers are dumb pipes.

See `AI_DESIGN.md` §2, §17 and `EDGE_DEFENSE.md` §3, §4 for the full interfaces.

---

## 5. Configuration parsing

- **Hand-rolled, no `build_runner`.** WebSight deliberately moved away from `json_serializable` for new feature configs (see `lib/config/feature_configs.dart` and the comments there). New configs follow the same pattern.

- **Use the `_typed<T>` helper.** Defined in `feature_configs.dart`. Extracts a typed map / list / scalar from a `dynamic` YAML node, returning null if the type doesn't match. Continue this for `ai_config.dart`:

    ```dart
    factory AiConfig.fromMap(Map<String, dynamic>? raw) {
      if (raw == null) return AiConfig.disabled();
      return AiConfig(
        enabled: raw['enabled'] as bool? ?? false,
        preset: raw['preset'] as String? ?? 'co_pilot',
        memory: MemoryConfig.fromMap(_typed<Map<String, dynamic>>(raw['memory'])),
        // ...
      );
    }
    ```

- **Validate at parse time.** Throw `ConfigureError` (the existing exception) with a clear message if `preset: co_pilot` is paired with `user_configurable.home_url: true`, or if a referenced provider isn't in `byok.providers`. Failing fast at YAML load is better than failing at runtime.

- **Defaults belong in the config class, not in callers.** `(raw['enabled'] as bool?) ?? false` lives in the factory; nothing downstream should re-default.

---

## 6. Imports

- **Use `package:` prefix for everything in `lib/`.** `import 'package:websight_ai/ai/agent_loop.dart';` — not relative imports. WebSight's `analysis_options.yaml` enforces `always_use_package_imports`.
- **`tool/` is the exception.** Files under `tool/` use relative imports (the WebSight precedent — see `tool/configure.dart`'s `// ignore_for_file` directive).
- **Order:**
  1. `dart:` imports
  2. blank line
  3. `package:` imports (alphabetical)
  4. blank line
  5. relative imports (only inside `tool/`, alphabetical)
- **No wildcard imports** (`show` / `hide` clauses are fine when needed for disambiguation, e.g., `import 'package:flutter/material.dart' hide ActionDispatcher;` per WebSight's existing usage).

---

## 7. Dart preferences

- **`final` by default.** Mutable variables need a reason. Class fields default to `final`; `var` only when reassignment is needed.
- **`const` where possible.** Constructors, instances, lists, maps. The lint will flag missed opportunities.
- **Avoid `late`.** Use only when:
  - Field initialization genuinely needs to be deferred to a constructor body
  - Field is non-nullable and tests need to mutate it
  - Otherwise, use a nullable field or initialize at declaration.
- **Prefer `List<T>` / `Map<K,V>` over `Iterable<T>`** when the consumer needs random access or knows the count. Use `Iterable` for streams of data the consumer iterates once.
- **Async/await over `.then`.** Rarely use `.then` — only for chaining where async/await is awkward.
- **Streams via `Stream` + `await for`** when consuming. `StreamController` only when bridging non-stream sources.

---

## 8. Comments and documentation

- **Module-level docstring on non-trivial files.** First class or top-level definition gets a `///` doc comment explaining the file's purpose and lifecycle. Match WebSight's tone — direct, technical, no marketing fluff.

    ```dart
    /// Owns the agent loop for one task. Streams events from the configured
    /// provider; dispatches tool calls through the executor; checkpoints
    /// hot context and flushes to episodic memory at task end.
    ///
    /// Disposed when the task ends or the user dismisses the chat panel.
    /// Construction does not start the loop — call [run] explicitly.
    class AgentLoop extends ChangeNotifier { ... }
    ```

- **`// TODO(name): ...` for known gaps.** Include who and why. Not just `// TODO`.
- **No commented-out code.** Delete it; git remembers.
- **Comment the *why*, not the *what*.** `// We serialize destructive actions even when the model returns them in parallel — see §9.2 of AI_DESIGN.md.` is useful. `// Loop through the actions` is not.

---

## 9. YAML conventions

- **Keys: `snake_case`.** `restrict_to_hosts`, `untrusted_action`, `auto_extract_enabled`. Match WebSight's existing schema.
- **String values: double-quoted** when they could otherwise be misparsed (URLs, hosts, expressions). Bare strings only for clearly-unambiguous values (`true`, `false`, `none`, `auto`, single-word identifiers).
- **Comments above each section** with a one-line explanation of the section's purpose. Match the existing `webview_config.yaml`.
- **Comments above non-obvious keys** explaining behavior. The reference config (`docs/internal/config-reference.yaml`) is the long-form annotation source; the live YAML can be terser.
- **Emoji status markers in the canonical reference only.** The live `webview_config.yaml` doesn't use ✅/🛠/🚧; those belong in `docs/internal/config-reference.yaml`.

---

## 10. Tests

See [`docs/AI_TEST_STRATEGY.md`](docs/AI_TEST_STRATEGY.md) for what to test and how. A few naming conventions:

- **Test files live in `test/` mirroring `lib/` exactly.**
- **Top-level `group(...)` per class under test.** Then nested `group(...)` per method or behavior cluster, then `test(...)` or `testWidgets(...)` for individual cases.
- **Test names describe behavior, not implementation.**
  - ✗ `test('calls notifyListeners')`
  - ✓ `test('emits change when key is replaced')`
- **Arrange / act / assert with blank lines between phases** for readability when the test is non-trivial.
- **Fixtures in `test/fixtures/`.** Canned provider responses, sample YAML, etc.
- **`pumpEventQueue()` and `pumpAndSettle()` cautiously.** Both can mask bugs. Prefer explicit waits on specific futures.

---

## 11. Logging and observability

- **Three log levels, used deliberately.**
  - `debugPrint` (gated by `kDebugMode`) — verbose dev-only.
  - Crashlytics non-fatal — recoverable errors that the integrator wants visibility into. Match `BillingController.lastError` pattern. **Never log conversation content, page content, or memory content.**
  - Audit log — every navigation attempt, every destructive action, every tool call (with redacted args). User-visible in settings.
- **Redaction is mandatory before any log.** Fields named `password`, `token`, `key`, `secret`, `cardNumber`, `ssn` (and any field adjacent to those terms) are replaced with `***` before reaching any log surface. Build a single redaction utility in `lib/ai/redaction.dart` and use it everywhere — don't reinvent per call site.

---

## 12. Git and process

- **Branch naming: `<type>/<short-description>`.** `feat/agent-loop`, `fix/host-matcher-wildcard`, `docs/spec-v0-5`, `refactor/memory-router`. Lowercase, hyphen-separated.
- **Commit messages: imperative mood, present tense.** "Add memory router heuristic." "Fix wildcard match for `*.example.com`." Not "Added" or "Adds."
- **Conventional commits are not required**, but if you use them, be consistent.
- **PRs are small.** Every PR in the ladder (see `AI_SPEC.md` §7) is roughly one feature or one refactor. If a PR touches more than ~600 lines of non-trivial code, split it.
- **Every PR runs the full CI gate.** Format check, `flutter analyze`, `flutter test --coverage`, debug Android build. None of these may regress.
- **Linear history on `main`: squash-merge or rebase-merge, not merge commits.** The AI fork keeps `main` linear so the mainline narrative reads as one commit per PR. Within a feature branch, prefer small per-concern commits so review can follow the work; squash combines them into a single mainline commit at merge. See `CLAUDE.md` §3 for the operating policy.
- **PR description includes:** what changed, why, what's tested, what's deferred, any spec drift introduced.

---

## 13. When in doubt

Read the existing WebSight code in the area you're modifying. The conventions above are derived from it; if something looks inconsistent with this doc, **the existing code wins** and we update the doc.

If the existing code is genuinely wrong (rare; WebSight is well-curated), open a separate refactor PR before adding new code on top — don't bundle inconsistency into a feature PR.
