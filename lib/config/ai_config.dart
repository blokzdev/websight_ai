/// Typed parser for the `ai:` block in `assets/webview_config.yaml`.
///
/// Mirrors the locked YAML schema in `docs/AI_DESIGN.md` §10. Hand-rolled
/// using the `_typed<T>` pattern from `lib/config/feature_configs.dart`
/// (no `build_runner`, no `json_serializable`). Schema is the contract;
/// the v1 first-PR scaffold parses every block — `ai.security.*`,
/// `ai.edge_defense.*`, `ai.billing.*`, `ai.router.*` — even though no
/// runtime code consumes them yet.
///
/// Default state when the YAML lacks an `ai:` key (or `ai.enabled: false`)
/// is [AiConfig.disabled]: a fully-defaulted, agent-runtime-off
/// configuration. Existing WebSight behaviour is unchanged.
///
/// Validation throws [AiConfigError] at parse time for:
///   * `preset` outside {`co_pilot`, `browser`}
///   * `preset: co_pilot` combined with `user_configurable.home_url: true`
///   * `byok.providers` referencing a provider not in
///     {`anthropic`, `openai`, `google`}
///   * `billing.mode` outside {`byok`, `managed`, `local`}
///   * `billing.mode: managed` or `local` in v1 (architecturally accepted,
///     not yet honored — see `AI_DESIGN.md` §1.4)
library;

import 'package:flutter/foundation.dart';

// -----------------------------------------------------------------------------
// Helpers — duplicate the private extraction pattern from
// `feature_configs.dart` so this file stays self-contained. If a future PR
// wants to lift these into a shared helper, that's a deliberate refactor
// (CLAUDE.md §8 — no drive-by changes in scaffolding PRs).
// -----------------------------------------------------------------------------

T? _typed<T>(Object? v) => v is T ? v : null;

bool _bool(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

int _int(Object? v, {int fallback = 0}) =>
    v is int ? v : (v is num ? v.toInt() : fallback);

String _str(Object? v, {String fallback = ''}) => v is String ? v : fallback;

String? _strOrNull(Object? v) => v is String ? v : null;

List<String> _strList(Object? v) => v is List
    ? v.whereType<String>().toList(growable: false)
    : const <String>[];

Map<String, String> _strStrMap(Object? v) {
  if (v is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in v.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

/// Thrown by [AiConfig.fromMap] when the parsed YAML violates a schema
/// invariant or carries a value v1 cannot honor.
///
/// Parallels the `ConfigureError` exception in `tool/configure_lib.dart`;
/// kept separate because that one lives outside `lib/` and is scoped to
/// the configure CLI. A future PR may unify the two.
class AiConfigError implements Exception {
  AiConfigError(this.message);
  final String message;
  @override
  String toString() => 'AiConfigError: $message';
}

// -----------------------------------------------------------------------------
// Allowed identifier sets
// -----------------------------------------------------------------------------

const Set<String> _allowedPresets = {'co_pilot', 'browser'};
const Set<String> _allowedProviders = {'anthropic', 'openai', 'google'};
const Set<String> _allowedBillingModes = {'byok', 'managed', 'local'};

// -----------------------------------------------------------------------------
// AiConfig — root
// -----------------------------------------------------------------------------

/// Root of the parsed `ai:` YAML block.
@immutable
class AiConfig {
  const AiConfig({
    required this.enabled,
    required this.preset,
    required this.userConfigurable,
    required this.presets,
    required this.byok,
    required this.navigationPolicy,
    required this.autonomy,
    required this.dock,
    required this.budgets,
    required this.pageReader,
    required this.memory,
    required this.privacy,
    required this.security,
    required this.edgeDefense,
    required this.billing,
    required this.router,
  });

  final bool enabled;
  final String preset;
  final UserConfigurableConfig userConfigurable;
  final List<PresetEntry> presets;
  final ByokConfig byok;
  final NavigationPolicyConfig navigationPolicy;
  final AutonomyConfig autonomy;
  final DockConfig dock;
  final BudgetsConfig budgets;
  final PageReaderConfig pageReader;
  final MemoryConfig memory;
  final PrivacyConfig privacy;
  final SecurityConfig security;
  final EdgeDefenseConfig edgeDefense;
  final BillingConfig billing;
  final RouterConfig router;

  /// Disabled default — used when the YAML has no `ai:` key.
  /// Every sub-block falls back to its own neutral defaults.
  factory AiConfig.disabled() => AiConfig(
        enabled: false,
        preset: 'co_pilot',
        userConfigurable: UserConfigurableConfig.defaults(),
        presets: const <PresetEntry>[],
        byok: ByokConfig.defaults(),
        navigationPolicy: NavigationPolicyConfig.defaults(),
        autonomy: AutonomyConfig.defaults(),
        dock: DockConfig.defaults(),
        budgets: BudgetsConfig.defaults(),
        pageReader: PageReaderConfig.defaults(),
        memory: MemoryConfig.defaults(),
        privacy: PrivacyConfig.defaults(),
        security: SecurityConfig.defaults(),
        edgeDefense: EdgeDefenseConfig.defaults(),
        billing: BillingConfig.defaults(),
        router: RouterConfig.defaults(),
      );

  factory AiConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return AiConfig.disabled();

    final preset = _str(raw['preset'], fallback: 'co_pilot');
    if (!_allowedPresets.contains(preset)) {
      throw AiConfigError(
        'ai.preset must be one of $_allowedPresets; got "$preset"',
      );
    }

    final userConfigurable = UserConfigurableConfig.fromMap(
      _typed<Map<String, dynamic>>(raw['user_configurable']),
    );
    if (preset == 'co_pilot' && userConfigurable.homeUrl) {
      throw AiConfigError(
        'ai.preset "co_pilot" cannot set ai.user_configurable.home_url '
        'true; that flag is browser-preset only.',
      );
    }
    if (preset == 'co_pilot' && userConfigurable.trustedDomains) {
      throw AiConfigError(
        'ai.preset "co_pilot" cannot set ai.user_configurable.'
        'trusted_domains true; that flag is browser-preset only.',
      );
    }

    final byok = ByokConfig.fromMap(_typed<Map<String, dynamic>>(raw['byok']));
    for (final p in byok.providers) {
      if (!_allowedProviders.contains(p)) {
        throw AiConfigError(
          'ai.byok.providers entry "$p" is not in $_allowedProviders',
        );
      }
    }
    if (byok.providers.isNotEmpty &&
        !byok.providers.contains(byok.defaultProvider)) {
      throw AiConfigError(
        'ai.byok.default_provider "${byok.defaultProvider}" is not in '
        'ai.byok.providers ${byok.providers}',
      );
    }

    final billing =
        BillingConfig.fromMap(_typed<Map<String, dynamic>>(raw['billing']));
    if (!_allowedBillingModes.contains(billing.mode)) {
      throw AiConfigError(
        'ai.billing.mode must be one of $_allowedBillingModes; '
        'got "${billing.mode}"',
      );
    }
    if (billing.mode != 'byok') {
      throw AiConfigError(
        'ai.billing.mode "${billing.mode}" is architecturally supported but '
        'not yet honored in v1; only "byok" is honored. The managed-credits '
        'mode lands in v1.5; local-only mode lands in v2 on Tier A+ devices. '
        'See AI_DESIGN.md §1.4.',
      );
    }

    return AiConfig(
      enabled: _bool(raw['enabled']),
      preset: preset,
      userConfigurable: userConfigurable,
      presets: _parsePresets(raw['presets']),
      byok: byok,
      navigationPolicy: NavigationPolicyConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['navigation_policy']),
      ),
      autonomy: AutonomyConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['autonomy']),
      ),
      dock: DockConfig.fromMap(_typed<Map<String, dynamic>>(raw['dock'])),
      budgets:
          BudgetsConfig.fromMap(_typed<Map<String, dynamic>>(raw['budgets'])),
      pageReader: PageReaderConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['page_reader']),
      ),
      memory:
          MemoryConfig.fromMap(_typed<Map<String, dynamic>>(raw['memory'])),
      privacy:
          PrivacyConfig.fromMap(_typed<Map<String, dynamic>>(raw['privacy'])),
      security: SecurityConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['security']),
      ),
      edgeDefense: EdgeDefenseConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['edge_defense']),
      ),
      billing: billing,
      router:
          RouterConfig.fromMap(_typed<Map<String, dynamic>>(raw['router'])),
    );
  }

  static List<PresetEntry> _parsePresets(Object? raw) {
    if (raw is! List) return const <PresetEntry>[];
    final out = <PresetEntry>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(PresetEntry.fromMap(Map<String, dynamic>.from(item)));
      }
    }
    return List<PresetEntry>.unmodifiable(out);
  }
}

// -----------------------------------------------------------------------------
// UserConfigurableConfig
// -----------------------------------------------------------------------------

@immutable
class UserConfigurableConfig {
  const UserConfigurableConfig({
    required this.homeUrl,
    required this.trustedDomains,
    required this.autonomy,
    required this.requireValidation,
  });

  final bool homeUrl;
  final bool trustedDomains;
  final bool autonomy;
  final bool requireValidation;

  factory UserConfigurableConfig.defaults() => const UserConfigurableConfig(
        homeUrl: false,
        trustedDomains: false,
        autonomy: true,
        requireValidation: true,
      );

  factory UserConfigurableConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return UserConfigurableConfig.defaults();
    return UserConfigurableConfig(
      homeUrl: _bool(raw['home_url']),
      trustedDomains: _bool(raw['trusted_domains']),
      autonomy: _bool(raw['autonomy'], fallback: true),
      requireValidation: _bool(raw['require_validation'], fallback: true),
    );
  }
}

// -----------------------------------------------------------------------------
// PresetEntry (curated starter sites for browser preset)
// -----------------------------------------------------------------------------

@immutable
class PresetEntry {
  const PresetEntry({
    required this.name,
    required this.homeUrl,
    required this.trustedDomains,
  });

  final String name;
  final String homeUrl;
  final List<String> trustedDomains;

  factory PresetEntry.fromMap(Map<String, dynamic> raw) => PresetEntry(
        name: _str(raw['name']),
        homeUrl: _str(raw['home_url']),
        trustedDomains: _strList(raw['trusted_domains']),
      );
}

// -----------------------------------------------------------------------------
// ByokConfig
// -----------------------------------------------------------------------------

@immutable
class ByokConfig {
  const ByokConfig({
    required this.required,
    required this.providers,
    required this.defaultProvider,
    required this.defaultModel,
    required this.embeddingsProvider,
  });

  final bool required;
  final List<String> providers;
  final String defaultProvider;
  final Map<String, String> defaultModel;
  final String embeddingsProvider;

  factory ByokConfig.defaults() => const ByokConfig(
        required: true,
        providers: <String>[],
        defaultProvider: 'anthropic',
        defaultModel: <String, String>{},
        embeddingsProvider: 'voyage',
      );

  factory ByokConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return ByokConfig.defaults();
    return ByokConfig(
      required: _bool(raw['required'], fallback: true),
      providers: _strList(raw['providers']),
      defaultProvider: _str(raw['default_provider'], fallback: 'anthropic'),
      defaultModel: _strStrMap(raw['default_model']),
      embeddingsProvider: _str(raw['embeddings_provider'], fallback: 'voyage'),
    );
  }
}

// -----------------------------------------------------------------------------
// NavigationPolicyConfig
// -----------------------------------------------------------------------------

@immutable
class NavigationPolicyConfig {
  const NavigationPolicyConfig({
    required this.homeOnly,
    required this.trustedDomains,
    required this.untrustedAction,
    required this.logAllNavigations,
  });

  final bool homeOnly;
  final List<String> trustedDomains;
  final String untrustedAction;
  final bool logAllNavigations;

  factory NavigationPolicyConfig.defaults() => const NavigationPolicyConfig(
        homeOnly: false,
        trustedDomains: <String>[],
        untrustedAction: 'prompt',
        logAllNavigations: true,
      );

  factory NavigationPolicyConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return NavigationPolicyConfig.defaults();
    return NavigationPolicyConfig(
      homeOnly: _bool(raw['home_only']),
      trustedDomains: _strList(raw['trusted_domains']),
      untrustedAction: _str(raw['untrusted_action'], fallback: 'prompt'),
      logAllNavigations: _bool(raw['log_all_navigations'], fallback: true),
    );
  }
}

// -----------------------------------------------------------------------------
// AutonomyConfig
// -----------------------------------------------------------------------------

@immutable
class AutonomyConfig {
  const AutonomyConfig({
    required this.actionDefaults,
    required this.perHostOverrides,
  });

  final ActionDefaultsConfig actionDefaults;
  final Map<String, String> perHostOverrides;

  factory AutonomyConfig.defaults() => AutonomyConfig(
        actionDefaults: ActionDefaultsConfig.defaults(),
        perHostOverrides: const <String, String>{},
      );

  factory AutonomyConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return AutonomyConfig.defaults();
    return AutonomyConfig(
      actionDefaults: ActionDefaultsConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['action_defaults']),
      ),
      perHostOverrides: _strStrMap(raw['per_host_overrides']),
    );
  }
}

@immutable
class ActionDefaultsConfig {
  const ActionDefaultsConfig({
    required this.pageInteractions,
    required this.crossHostNavigation,
    required this.formSubmits,
    required this.nativeActions,
  });

  final String pageInteractions;
  final String crossHostNavigation;
  final String formSubmits;
  final String nativeActions;

  factory ActionDefaultsConfig.defaults() => const ActionDefaultsConfig(
        pageInteractions: 'auto',
        crossHostNavigation: 'confirm',
        formSubmits: 'confirm',
        nativeActions: 'confirm',
      );

  factory ActionDefaultsConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return ActionDefaultsConfig.defaults();
    return ActionDefaultsConfig(
      pageInteractions: _str(raw['page_interactions'], fallback: 'auto'),
      crossHostNavigation:
          _str(raw['cross_host_navigation'], fallback: 'confirm'),
      formSubmits: _str(raw['form_submits'], fallback: 'confirm'),
      nativeActions: _str(raw['native_actions'], fallback: 'confirm'),
    );
  }
}

// -----------------------------------------------------------------------------
// DockConfig
// -----------------------------------------------------------------------------

@immutable
class DockConfig {
  const DockConfig({
    required this.enabled,
    required this.initialPosition,
    required this.hideable,
    required this.showOnFirstLaunch,
  });

  final bool enabled;
  final String initialPosition;
  final bool hideable;
  final bool showOnFirstLaunch;

  factory DockConfig.defaults() => const DockConfig(
        enabled: true,
        initialPosition: 'bottom_right',
        hideable: true,
        showOnFirstLaunch: true,
      );

  factory DockConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return DockConfig.defaults();
    return DockConfig(
      enabled: _bool(raw['enabled'], fallback: true),
      initialPosition:
          _str(raw['initial_position'], fallback: 'bottom_right'),
      hideable: _bool(raw['hideable'], fallback: true),
      showOnFirstLaunch:
          _bool(raw['show_on_first_launch'], fallback: true),
    );
  }
}

// -----------------------------------------------------------------------------
// BudgetsConfig
// -----------------------------------------------------------------------------

@immutable
class BudgetsConfig {
  const BudgetsConfig({
    required this.softTokenLimitPerTask,
    required this.hardTokenLimitPerTask,
    required this.softStepThreshold,
    required this.monthlyTokenWarning,
  });

  final int softTokenLimitPerTask;
  final int hardTokenLimitPerTask;
  final int softStepThreshold;
  final int monthlyTokenWarning;

  factory BudgetsConfig.defaults() => const BudgetsConfig(
        softTokenLimitPerTask: 50000,
        hardTokenLimitPerTask: 100000,
        softStepThreshold: 30,
        monthlyTokenWarning: 5000000,
      );

  factory BudgetsConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return BudgetsConfig.defaults();
    return BudgetsConfig(
      softTokenLimitPerTask:
          _int(raw['soft_token_limit_per_task'], fallback: 50000),
      hardTokenLimitPerTask:
          _int(raw['hard_token_limit_per_task'], fallback: 100000),
      softStepThreshold: _int(raw['soft_step_threshold'], fallback: 30),
      monthlyTokenWarning:
          _int(raw['monthly_token_warning'], fallback: 5000000),
    );
  }
}

// -----------------------------------------------------------------------------
// PageReaderConfig
// -----------------------------------------------------------------------------

@immutable
class PageReaderConfig {
  const PageReaderConfig({
    required this.domDigest,
    required this.screenshotOnRequest,
    required this.setOfMarks,
    required this.diffSubsequentTurns,
    required this.perceptualHashDedup,
  });

  final bool domDigest;
  final bool screenshotOnRequest;
  final bool setOfMarks;
  final bool diffSubsequentTurns;
  final bool perceptualHashDedup;

  factory PageReaderConfig.defaults() => const PageReaderConfig(
        domDigest: true,
        screenshotOnRequest: true,
        setOfMarks: true,
        diffSubsequentTurns: true,
        perceptualHashDedup: true,
      );

  factory PageReaderConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return PageReaderConfig.defaults();
    return PageReaderConfig(
      domDigest: _bool(raw['dom_digest'], fallback: true),
      screenshotOnRequest:
          _bool(raw['screenshot_on_request'], fallback: true),
      setOfMarks: _bool(raw['set_of_marks'], fallback: true),
      diffSubsequentTurns:
          _bool(raw['diff_subsequent_turns'], fallback: true),
      perceptualHashDedup:
          _bool(raw['perceptual_hash_dedup'], fallback: true),
    );
  }
}

// -----------------------------------------------------------------------------
// MemoryConfig + nested router/retention
// -----------------------------------------------------------------------------

@immutable
class MemoryConfig {
  const MemoryConfig({
    required this.coreEnabled,
    required this.episodicEnabled,
    required this.semanticEnabled,
    required this.resourceEnabled,
    required this.proceduralEnabled,
    required this.auditLogEnabled,
    required this.embeddingsEnabled,
    required this.autoExtractEnabled,
    required this.router,
    required this.retention,
  });

  final bool coreEnabled;
  final bool episodicEnabled;
  final bool semanticEnabled;
  final bool resourceEnabled;
  final bool proceduralEnabled;
  final bool auditLogEnabled;
  final bool embeddingsEnabled;
  final bool autoExtractEnabled;
  final MemoryRouterConfig router;
  final MemoryRetentionConfig retention;

  factory MemoryConfig.defaults() => MemoryConfig(
        coreEnabled: true,
        episodicEnabled: true,
        semanticEnabled: true,
        resourceEnabled: false,
        proceduralEnabled: false,
        auditLogEnabled: true,
        embeddingsEnabled: true,
        autoExtractEnabled: true,
        router: MemoryRouterConfig.defaults(),
        retention: MemoryRetentionConfig.defaults(),
      );

  factory MemoryConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return MemoryConfig.defaults();
    return MemoryConfig(
      coreEnabled: _bool(raw['core_enabled'], fallback: true),
      episodicEnabled: _bool(raw['episodic_enabled'], fallback: true),
      semanticEnabled: _bool(raw['semantic_enabled'], fallback: true),
      resourceEnabled: _bool(raw['resource_enabled']),
      proceduralEnabled: _bool(raw['procedural_enabled']),
      auditLogEnabled: _bool(raw['audit_log_enabled'], fallback: true),
      embeddingsEnabled: _bool(raw['embeddings_enabled'], fallback: true),
      autoExtractEnabled: _bool(raw['auto_extract_enabled'], fallback: true),
      router: MemoryRouterConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['router']),
      ),
      retention: MemoryRetentionConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['retention']),
      ),
    );
  }
}

@immutable
class MemoryRouterConfig {
  const MemoryRouterConfig({
    required this.strategy,
    required this.escalateOnAmbiguity,
  });

  final String strategy;
  final bool escalateOnAmbiguity;

  factory MemoryRouterConfig.defaults() => const MemoryRouterConfig(
        strategy: 'heuristic',
        escalateOnAmbiguity: true,
      );

  factory MemoryRouterConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return MemoryRouterConfig.defaults();
    return MemoryRouterConfig(
      strategy: _str(raw['strategy'], fallback: 'heuristic'),
      escalateOnAmbiguity:
          _bool(raw['escalate_on_ambiguity'], fallback: true),
    );
  }
}

@immutable
class MemoryRetentionConfig {
  const MemoryRetentionConfig({
    required this.episodicDays,
    required this.maxEpisodicRows,
  });

  /// `0` means keep forever (per `AI_DESIGN.md` §10).
  final int episodicDays;
  final int maxEpisodicRows;

  factory MemoryRetentionConfig.defaults() => const MemoryRetentionConfig(
        episodicDays: 0,
        maxEpisodicRows: 100000,
      );

  factory MemoryRetentionConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return MemoryRetentionConfig.defaults();
    return MemoryRetentionConfig(
      episodicDays: _int(raw['episodic_days']),
      maxEpisodicRows: _int(raw['max_episodic_rows'], fallback: 100000),
    );
  }
}

// -----------------------------------------------------------------------------
// PrivacyConfig
// -----------------------------------------------------------------------------

@immutable
class PrivacyConfig {
  const PrivacyConfig({
    required this.crashReporting,
    required this.anonymousUsageTelemetry,
  });

  final String crashReporting;
  final bool anonymousUsageTelemetry;

  factory PrivacyConfig.defaults() => const PrivacyConfig(
        crashReporting: 'ask_at_onboarding',
        anonymousUsageTelemetry: false,
      );

  factory PrivacyConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return PrivacyConfig.defaults();
    return PrivacyConfig(
      crashReporting:
          _str(raw['crash_reporting'], fallback: 'ask_at_onboarding'),
      anonymousUsageTelemetry: _bool(raw['anonymous_usage_telemetry']),
    );
  }
}

// -----------------------------------------------------------------------------
// SecurityConfig + nested paraphrase
// -----------------------------------------------------------------------------

@immutable
class SecurityConfig {
  const SecurityConfig({
    required this.sanitizationEnabled,
    required this.spotlightingEnabled,
    required this.classifierMode,
    required this.paraphrase,
    required this.selfReflectEnabled,
    required this.selfReflectExecution,
  });

  final bool sanitizationEnabled;
  final bool spotlightingEnabled;
  final String classifierMode;
  final ParaphraseConfig paraphrase;
  final bool selfReflectEnabled;
  final String selfReflectExecution;

  factory SecurityConfig.defaults() => SecurityConfig(
        sanitizationEnabled: true,
        spotlightingEnabled: true,
        classifierMode: 'edge_preferred',
        paraphrase: ParaphraseConfig.defaults(),
        selfReflectEnabled: true,
        selfReflectExecution: 'edge_preferred',
      );

  factory SecurityConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return SecurityConfig.defaults();
    return SecurityConfig(
      sanitizationEnabled:
          _bool(raw['sanitization_enabled'], fallback: true),
      spotlightingEnabled:
          _bool(raw['spotlighting_enabled'], fallback: true),
      classifierMode:
          _str(raw['classifier_mode'], fallback: 'edge_preferred'),
      paraphrase: ParaphraseConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['paraphrase']),
      ),
      selfReflectEnabled:
          _bool(raw['self_reflect_enabled'], fallback: true),
      selfReflectExecution:
          _str(raw['self_reflect_execution'], fallback: 'edge_preferred'),
    );
  }
}

@immutable
class ParaphraseConfig {
  const ParaphraseConfig({
    required this.enabled,
    required this.highRiskHosts,
    required this.onClassifierFlag,
    required this.execution,
    required this.cloudFallbackModel,
  });

  final bool enabled;
  final List<String> highRiskHosts;
  final bool onClassifierFlag;
  final String execution;
  final ParaphraseCloudFallbackModelConfig cloudFallbackModel;

  factory ParaphraseConfig.defaults() => ParaphraseConfig(
        enabled: false,
        highRiskHosts: const <String>[],
        onClassifierFlag: true,
        execution: 'edge_preferred',
        cloudFallbackModel: ParaphraseCloudFallbackModelConfig.defaults(),
      );

  factory ParaphraseConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return ParaphraseConfig.defaults();
    return ParaphraseConfig(
      enabled: _bool(raw['enabled']),
      highRiskHosts: _strList(raw['high_risk_hosts']),
      onClassifierFlag:
          _bool(raw['on_classifier_flag'], fallback: true),
      execution: _str(raw['execution'], fallback: 'edge_preferred'),
      cloudFallbackModel: ParaphraseCloudFallbackModelConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['cloud_fallback_model']),
      ),
    );
  }
}

@immutable
class ParaphraseCloudFallbackModelConfig {
  const ParaphraseCloudFallbackModelConfig({
    required this.provider,
    required this.model,
  });

  final String provider;
  final String model;

  factory ParaphraseCloudFallbackModelConfig.defaults() =>
      const ParaphraseCloudFallbackModelConfig(
        provider: 'anthropic',
        model: 'claude-haiku-4-5',
      );

  factory ParaphraseCloudFallbackModelConfig.fromMap(
      Map<String, dynamic>? raw) {
    if (raw == null) return ParaphraseCloudFallbackModelConfig.defaults();
    return ParaphraseCloudFallbackModelConfig(
      provider: _str(raw['provider'], fallback: 'anthropic'),
      model: _str(raw['model'], fallback: 'claude-haiku-4-5'),
    );
  }
}

// -----------------------------------------------------------------------------
// EdgeDefenseConfig
// -----------------------------------------------------------------------------

@immutable
class EdgeDefenseConfig {
  const EdgeDefenseConfig({
    required this.mode,
    required this.downloadStrategy,
    required this.fallbackOnQuota,
    required this.showQuotaIndicator,
  });

  final String mode;
  final String downloadStrategy;
  final bool fallbackOnQuota;
  final String showQuotaIndicator;

  factory EdgeDefenseConfig.defaults() => const EdgeDefenseConfig(
        mode: 'auto',
        downloadStrategy: 'lazy',
        fallbackOnQuota: true,
        showQuotaIndicator: 'near_exhaustion',
      );

  factory EdgeDefenseConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return EdgeDefenseConfig.defaults();
    return EdgeDefenseConfig(
      mode: _str(raw['mode'], fallback: 'auto'),
      downloadStrategy: _str(raw['download_strategy'], fallback: 'lazy'),
      fallbackOnQuota: _bool(raw['fallback_on_quota'], fallback: true),
      showQuotaIndicator:
          _str(raw['show_quota_indicator'], fallback: 'near_exhaustion'),
    );
  }
}

// -----------------------------------------------------------------------------
// BillingConfig + nested byok/managed/local
// -----------------------------------------------------------------------------

@immutable
class BillingConfig {
  const BillingConfig({
    required this.mode,
    required this.byok,
    required this.managed,
    required this.local,
  });

  final String mode;
  final BillingByokConfig byok;
  final BillingManagedConfig managed;
  final BillingLocalConfig local;

  factory BillingConfig.defaults() => BillingConfig(
        mode: 'byok',
        byok: BillingByokConfig.defaults(),
        managed: BillingManagedConfig.defaults(),
        local: BillingLocalConfig.defaults(),
      );

  factory BillingConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return BillingConfig.defaults();
    return BillingConfig(
      mode: _str(raw['mode'], fallback: 'byok'),
      byok: BillingByokConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['byok']),
      ),
      managed: BillingManagedConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['managed']),
      ),
      local: BillingLocalConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['local']),
      ),
    );
  }
}

@immutable
class BillingByokConfig {
  const BillingByokConfig({required this.providers});

  /// Provider-security-posture metadata, keyed by provider id
  /// (`anthropic`, `openai`, `google`). Values carry recommended status,
  /// `supported_models`, optional `warn_below_model`, etc., per
  /// `AI_DESIGN.md` §9.7. Parsed as opaque maps in v1 — schema lives in
  /// YAML; the BYOK onboarding UI (PR 2) reads this.
  final Map<String, Map<String, dynamic>> providers;

  factory BillingByokConfig.defaults() => const BillingByokConfig(
        providers: <String, Map<String, dynamic>>{},
      );

  factory BillingByokConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return BillingByokConfig.defaults();
    final providersRaw = raw['providers'];
    if (providersRaw is! Map) return BillingByokConfig.defaults();
    final providers = <String, Map<String, dynamic>>{};
    for (final entry in providersRaw.entries) {
      if (entry.key is String && entry.value is Map) {
        providers[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    return BillingByokConfig(providers: providers);
  }
}

@immutable
class BillingManagedConfig {
  const BillingManagedConfig({
    required this.proxyEndpoint,
    required this.freeTrialCredits,
  });

  final String proxyEndpoint;
  final int freeTrialCredits;

  factory BillingManagedConfig.defaults() => const BillingManagedConfig(
        proxyEndpoint: '',
        freeTrialCredits: 100,
      );

  factory BillingManagedConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return BillingManagedConfig.defaults();
    return BillingManagedConfig(
      proxyEndpoint: _str(raw['proxy_endpoint']),
      freeTrialCredits: _int(raw['free_trial_credits'], fallback: 100),
    );
  }
}

@immutable
class BillingLocalConfig {
  const BillingLocalConfig({required this.requireTier});

  final String requireTier;

  factory BillingLocalConfig.defaults() =>
      const BillingLocalConfig(requireTier: 'A+');

  factory BillingLocalConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return BillingLocalConfig.defaults();
    return BillingLocalConfig(
      requireTier: _str(raw['require_tier'], fallback: 'A+'),
    );
  }
}

// -----------------------------------------------------------------------------
// RouterConfig + nested classifier/overrides/tier_mapping
// -----------------------------------------------------------------------------

@immutable
class RouterConfig {
  const RouterConfig({
    required this.preset,
    required this.showRoutingBadge,
    required this.classifier,
    required this.overrides,
    required this.crossProviderOverridesAllowed,
    required this.tierMapping,
  });

  final String preset;
  final bool showRoutingBadge;
  final RouterClassifierConfig classifier;
  final RouterOverridesConfig overrides;
  final bool crossProviderOverridesAllowed;
  final Map<String, Map<String, String>> tierMapping;

  factory RouterConfig.defaults() => RouterConfig(
        preset: 'balanced',
        showRoutingBadge: true,
        classifier: RouterClassifierConfig.defaults(),
        overrides: RouterOverridesConfig.defaults(),
        crossProviderOverridesAllowed: true,
        tierMapping: const <String, Map<String, String>>{},
      );

  factory RouterConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return RouterConfig.defaults();
    return RouterConfig(
      preset: _str(raw['preset'], fallback: 'balanced'),
      showRoutingBadge: _bool(raw['show_routing_badge'], fallback: true),
      classifier: RouterClassifierConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['classifier']),
      ),
      overrides: RouterOverridesConfig.fromMap(
        _typed<Map<String, dynamic>>(raw['overrides']),
      ),
      crossProviderOverridesAllowed: _bool(
        raw['cross_provider_overrides_allowed'],
        fallback: true,
      ),
      tierMapping: _parseTierMapping(raw['tier_mapping']),
    );
  }

  static Map<String, Map<String, String>> _parseTierMapping(Object? raw) {
    if (raw is! Map) return const <String, Map<String, String>>{};
    final out = <String, Map<String, String>>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is Map) {
        out[entry.key as String] = _strStrMap(entry.value);
      }
    }
    return out;
  }
}

@immutable
class RouterClassifierConfig {
  const RouterClassifierConfig({required this.mode});

  final String mode;

  factory RouterClassifierConfig.defaults() =>
      const RouterClassifierConfig(mode: 'heuristic');

  factory RouterClassifierConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return RouterClassifierConfig.defaults();
    return RouterClassifierConfig(
      mode: _str(raw['mode'], fallback: 'heuristic'),
    );
  }
}

@immutable
class RouterOverridesConfig {
  const RouterOverridesConfig({
    required this.routine,
    required this.reasoning,
    required this.heavy,
  });

  /// `null` means "use the preset's default for this class".
  final String? routine;
  final String? reasoning;
  final String? heavy;

  factory RouterOverridesConfig.defaults() => const RouterOverridesConfig(
        routine: null,
        reasoning: null,
        heavy: null,
      );

  factory RouterOverridesConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return RouterOverridesConfig.defaults();
    return RouterOverridesConfig(
      routine: _strOrNull(raw['routine']),
      reasoning: _strOrNull(raw['reasoning']),
      heavy: _strOrNull(raw['heavy']),
    );
  }
}
