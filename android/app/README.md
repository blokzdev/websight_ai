# `android/app/` notes

## `google-services.json` — placeholder

The committed `google-services.json` carries **placeholder values**, not a
real Firebase project configuration. It is structured correctly so Gradle's
`com.google.gms.google-services` plugin will accept it and the debug APK
will build successfully, but Firebase services (Analytics, Crashlytics, FCM
push notifications) are **inert** until you regenerate it for your fork.

### Why this is a placeholder, not the real config

The upstream WebSight repo ships a real `google-services.json` tied to its
own Firebase project, which is appropriate for a template repo. WebSight AI
is a forked private product, not a template; committing real Firebase
credentials would:

- Tie the fork's Crashlytics / FCM telemetry to an account the fork
  doesn't control;
- Surface real OAuth client IDs in source control;
- Mismatch the new `applicationId` (`io.github.blokzdev.websight_ai`),
  causing Firebase to reject events at runtime anyway.

### Regenerating for a real Firebase project

When you (or a fork integrator) want Firebase services live:

1. Create a Firebase project at <https://console.firebase.google.com/>.
2. Add an Android app with package name `io.github.blokzdev.websight_ai`
   (or your own app id if you've forked again).
3. Download the generated `google-services.json` and replace this file.
4. Optionally use `flutterfire configure` for the same result plus
   `lib/firebase_options.dart` regeneration.

The runtime Firebase code paths in `lib/lifecycle/fcm_controller.dart`
and `lib/lifecycle/analytics_controller.dart` are gated by the
`notifications.fcm_enabled` and `analytics_crash.*` flags in
`assets/webview_config.yaml`, so a placeholder config plus disabled
flags is fully functional for development.
