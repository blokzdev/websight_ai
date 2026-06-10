# WebSight AI

[![CI](https://github.com/blokzdev/websight_ai/actions/workflows/ci.yml/badge.svg)](https://github.com/blokzdev/websight_ai/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)](https://flutter.dev)

**WebSight AI is an AI-native private fork of [WebSight](https://github.com/blokzdev/websight)** — a declarative Flutter Android WebView shell. The fork keeps WebSight's proven substrate (config-driven shell, hardened JS bridge, deterministic host enforcement) and layers on an agentic chat dock, JS-bridge agent tools, defense-in-depth against indirect prompt injection, and a task-class model router.

This repository is **not** a template. It is a forked product under active development toward v1 GA (Wikipedia co-pilot, Android-only, BYOK billing). Upstream WebSight remains the right starting point for general WebView-shell forks.

## Status

Pre-release. The directory tree, configuration schema, and identity are in place; the agent runtime, providers, defense pipeline, dock, and onboarding land in subsequent PRs along the ladder defined in [`AI_SPEC.md` §7](AI_SPEC.md). When `ai.enabled: false` (default), the app builds and runs as a stock WebView shell.

## Authoritative documents

Read these in order before contributing.

| Doc | Purpose |
|---|---|
| [`AI_SPEC.md`](AI_SPEC.md) | Vision, locked decisions, identity, release staging, PR ladder. |
| [`docs/AI_DESIGN.md`](docs/AI_DESIGN.md) | Full architecture: agent loop, providers, memory, defense pipeline, edge integration, YAML schema, directory layout. |
| [`docs/AI_THREAT_MODEL.md`](docs/AI_THREAT_MODEL.md) | DeepMind Agent Traps taxonomy, defense in depth, attack scenarios. |
| [`docs/EDGE_DEFENSE.md`](docs/EDGE_DEFENSE.md) | On-device defense execution: Gemini Nano via AICore (v1+); Apple Foundation Models (v3.x). |
| [`docs/AI_TEST_STRATEGY.md`](docs/AI_TEST_STRATEGY.md) | Test pyramid, fakes, security fixtures, CI gates, coverage thresholds. |
| [`CONVENTIONS.md`](CONVENTIONS.md) | Code style, naming, state management, imports, hand-rolled `_typed<T>` config pattern. |
| [`CLAUDE.md`](CLAUDE.md) | Operating contract for AI-assisted development sessions on this repo. |

For substrate documentation (WebView controller, JS bridge API, configure tool), see upstream WebSight's docs — the technical references in [`docs/bridge-api.md`](docs/bridge-api.md) and [`docs/internal/config-reference.yaml`](docs/internal/config-reference.yaml) are inherited verbatim.

## Locked decisions (don't casually revisit)

Mirrored from [`AI_SPEC.md` §6](AI_SPEC.md):

- Product name: **WebSight AI**.
- Application id: **`io.github.blokzdev.websight_ai`**.
- v1 spearhead: **Wikipedia co-pilot**.
- v1 minimum Android API: **34** (Android 14).
- v1 platform: **Android only**. iOS deferred to v3.x.
- Billing modes: **BYOK only in v1**, managed credits in v1.5, local-only in v2 on Tier A+ devices.
- Provider scope: **Anthropic, OpenAI, Google** (Anthropic recommended).
- Defense layer: edge-first; cloud fallback on Tier B/C devices.

## Development setup

1. Install a recent stable Flutter (Dart SDK ≥3.10 transitively required by `google_mobile_ads`).
2. `flutter pub get`.
3. For full Firebase functionality, replace `android/app/google-services.json` with a real config — see [`android/app/README.md`](android/app/README.md). The committed placeholder lets the app build cleanly without Firebase services.
4. `flutter run` or `flutter build apk --debug`.

### Verifying changes before pushing

The PR checklist in [`CLAUDE.md` §12](CLAUDE.md) is authoritative. Minimum:

```bash
dart format --set-exit-if-changed lib test tool
flutter analyze --no-fatal-infos
flutter test --coverage
flutter build apk --debug
```

All four are CI-enforced ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## Branch and PR discipline

`main` is protected by convention (free-tier private repo can't enforce mechanically). See [`CLAUDE.md` §3](CLAUDE.md) for the operating rules:

- Feature branches only — never commit to `main`.
- Linear history: squash-merge or rebase-merge; no merge commits on `main`.
- PR descriptions must include what / why / what was tested / deviations / PR ladder item from [`AI_SPEC.md` §7](AI_SPEC.md).

## License

Apache License 2.0 — see [`LICENSE`](LICENSE). Inherited from upstream WebSight.
