/*
 * WebSight AI — in-page agent helpers (stub).
 *
 * This file is the placeholder for the agent's in-page surface. It is
 * injected into the WebView alongside `assets/websight.js` (the existing
 * bridge facade) when `ai.enabled` is true in `assets/webview_config.yaml`.
 *
 * In v1 this file will host:
 *   - the sanitization pipeline (AI_THREAT_MODEL.md §4.5 / AI_DESIGN.md §4.5):
 *       sanitizeForAgent(node) — strip hidden elements, comments, off-screen
 *       content, length-capped aria/alt/title, custom-font glyph remapping.
 *   - the DOM digest emitter (AI_DESIGN.md §4.1): emits the compact
 *       hash-stable element-id JSON the agent reasons against.
 *   - the Set-of-Marks overlay injector (AI_DESIGN.md §4.2).
 *   - the action helpers (click / fill / scroll / waitFor) called via
 *       `WebSightBridge.agent.*` extensions.
 *
 * None of those land in this PR. The scaffolding-only first PR (AI_SPEC.md
 * §7 PR 1) creates the file as an empty IIFE so subsequent PRs have a
 * clear place to land and so the asset is bundled by `flutter pub get`.
 *
 * State discipline: this file is stateless (per AI_DESIGN.md §8). No
 * localStorage, sessionStorage, indexedDB, or document.cookie writes ever.
 * All agent state persists Dart-side.
 */

(function () {
  'use strict';
  // No exports yet. Wired in subsequent PRs (AI_SPEC.md §7 PR 3 onward).
})();
