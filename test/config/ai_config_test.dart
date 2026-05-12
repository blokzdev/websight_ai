import 'package:flutter_test/flutter_test.dart';
import 'package:websight_ai/config/ai_config.dart';

void main() {
  group('AiConfig.disabled', () {
    test('produces a fully-defaulted disabled config', () {
      final c = AiConfig.disabled();

      expect(c.enabled, isFalse);
      expect(c.preset, 'co_pilot');
      expect(c.presets, isEmpty);

      expect(c.userConfigurable.homeUrl, isFalse);
      expect(c.userConfigurable.trustedDomains, isFalse);
      expect(c.userConfigurable.autonomy, isTrue);
      expect(c.userConfigurable.requireValidation, isTrue);

      expect(c.byok.required, isTrue);
      expect(c.byok.providers, isEmpty);
      expect(c.byok.defaultProvider, 'anthropic');
      expect(c.byok.defaultModel, isEmpty);
      expect(c.byok.embeddingsProvider, 'voyage');

      expect(c.navigationPolicy.homeOnly, isFalse);
      expect(c.navigationPolicy.untrustedAction, 'prompt');
      expect(c.navigationPolicy.logAllNavigations, isTrue);

      expect(c.autonomy.actionDefaults.pageInteractions, 'auto');
      expect(c.autonomy.actionDefaults.crossHostNavigation, 'confirm');
      expect(c.autonomy.actionDefaults.formSubmits, 'confirm');
      expect(c.autonomy.actionDefaults.nativeActions, 'confirm');
      expect(c.autonomy.perHostOverrides, isEmpty);

      expect(c.dock.enabled, isTrue);
      expect(c.dock.initialPosition, 'bottom_right');
      expect(c.dock.hideable, isTrue);
      expect(c.dock.showOnFirstLaunch, isTrue);

      expect(c.budgets.softTokenLimitPerTask, 50000);
      expect(c.budgets.hardTokenLimitPerTask, 100000);
      expect(c.budgets.softStepThreshold, 30);
      expect(c.budgets.monthlyTokenWarning, 5000000);

      expect(c.pageReader.domDigest, isTrue);
      expect(c.pageReader.screenshotOnRequest, isTrue);
      expect(c.pageReader.setOfMarks, isTrue);
      expect(c.pageReader.diffSubsequentTurns, isTrue);
      expect(c.pageReader.perceptualHashDedup, isTrue);

      expect(c.memory.coreEnabled, isTrue);
      expect(c.memory.episodicEnabled, isTrue);
      expect(c.memory.semanticEnabled, isTrue);
      expect(c.memory.resourceEnabled, isFalse);
      expect(c.memory.proceduralEnabled, isFalse);
      expect(c.memory.auditLogEnabled, isTrue);
      expect(c.memory.embeddingsEnabled, isTrue);
      expect(c.memory.autoExtractEnabled, isTrue);
      expect(c.memory.router.strategy, 'heuristic');
      expect(c.memory.router.escalateOnAmbiguity, isTrue);
      expect(c.memory.retention.episodicDays, 0);
      expect(c.memory.retention.maxEpisodicRows, 100000);

      expect(c.privacy.crashReporting, 'ask_at_onboarding');
      expect(c.privacy.anonymousUsageTelemetry, isFalse);

      expect(c.security.sanitizationEnabled, isTrue);
      expect(c.security.spotlightingEnabled, isTrue);
      expect(c.security.classifierMode, 'edge_preferred');
      expect(c.security.paraphrase.enabled, isFalse);
      expect(c.security.paraphrase.onClassifierFlag, isTrue);
      expect(c.security.paraphrase.execution, 'edge_preferred');
      expect(c.security.paraphrase.cloudFallbackModel.provider, 'anthropic');
      expect(c.security.paraphrase.cloudFallbackModel.model,
          'claude-haiku-4-5');
      expect(c.security.selfReflectEnabled, isTrue);
      expect(c.security.selfReflectExecution, 'edge_preferred');

      expect(c.edgeDefense.mode, 'auto');
      expect(c.edgeDefense.downloadStrategy, 'lazy');
      expect(c.edgeDefense.fallbackOnQuota, isTrue);
      expect(c.edgeDefense.showQuotaIndicator, 'near_exhaustion');

      expect(c.billing.mode, 'byok');
      expect(c.billing.byok.providers, isEmpty);
      expect(c.billing.managed.proxyEndpoint, '');
      expect(c.billing.managed.freeTrialCredits, 100);
      expect(c.billing.local.requireTier, 'A+');

      expect(c.router.preset, 'balanced');
      expect(c.router.showRoutingBadge, isTrue);
      expect(c.router.classifier.mode, 'heuristic');
      expect(c.router.overrides.routine, isNull);
      expect(c.router.overrides.reasoning, isNull);
      expect(c.router.overrides.heavy, isNull);
      expect(c.router.crossProviderOverridesAllowed, isTrue);
      expect(c.router.tierMapping, isEmpty);
    });
  });

  group('AiConfig.fromMap', () {
    test('null map returns the disabled default', () {
      final c = AiConfig.fromMap(null);
      expect(c.enabled, isFalse);
      expect(c.preset, 'co_pilot');
    });

    test('enabled: true with minimal config parses without error', () {
      final c = AiConfig.fromMap(<String, dynamic>{'enabled': true});
      expect(c.enabled, isTrue);
      expect(c.preset, 'co_pilot');
      expect(c.billing.mode, 'byok');
    });

    test('full canonical schema round-trips correctly', () {
      final c = AiConfig.fromMap(_canonicalAiBlock());

      expect(c.enabled, isTrue);
      expect(c.preset, 'co_pilot');

      expect(c.userConfigurable.homeUrl, isFalse);
      expect(c.userConfigurable.trustedDomains, isFalse);
      expect(c.userConfigurable.autonomy, isTrue);

      expect(c.presets, hasLength(1));
      expect(c.presets.first.name, 'Hacker News');
      expect(c.presets.first.homeUrl, 'https://news.ycombinator.com');
      expect(c.presets.first.trustedDomains, ['*.ycombinator.com']);

      expect(c.byok.required, isTrue);
      expect(c.byok.providers,
          containsAll(<String>['anthropic', 'openai', 'google']));
      expect(c.byok.defaultProvider, 'anthropic');
      expect(c.byok.defaultModel['anthropic'], 'claude-opus-4-7');
      expect(c.byok.defaultModel['openai'], 'gpt-5');
      expect(c.byok.defaultModel['google'], 'gemini-2.5-pro');

      expect(c.security.paraphrase.highRiskHosts, isEmpty);
      expect(c.security.paraphrase.cloudFallbackModel.provider, 'anthropic');

      expect(c.billing.byok.providers, contains('anthropic'));
      expect(c.billing.byok.providers['anthropic']!['recommended'], isTrue);

      expect(c.router.tierMapping['anthropic'], isNotNull);
      expect(c.router.tierMapping['anthropic']!['routine'],
          'claude-haiku-4-5');
      expect(c.router.tierMapping['openai']!['heavy'], 'gpt-5');
      expect(c.router.tierMapping['google']!['reasoning'],
          'gemini-2.5-pro');
    });

    test('parses every block independently with neutral defaults filling gaps',
        () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'enabled': true,
        'memory': <String, dynamic>{
          'resource_enabled': true,
          'retention': <String, dynamic>{
            'episodic_days': 30,
            'max_episodic_rows': 50000,
          },
        },
      });
      expect(c.memory.resourceEnabled, isTrue);
      expect(c.memory.retention.episodicDays, 30);
      expect(c.memory.retention.maxEpisodicRows, 50000);
      // Other memory fields keep defaults.
      expect(c.memory.coreEnabled, isTrue);
      expect(c.memory.router.strategy, 'heuristic');
    });
  });

  group('AiConfig validation', () {
    test('rejects unknown preset', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{'preset': 'banana'}),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('ai.preset'),
        )),
      );
    });

    test('co_pilot preset rejects user_configurable.home_url: true', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'preset': 'co_pilot',
          'user_configurable': <String, dynamic>{'home_url': true},
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('home_url'),
        )),
      );
    });

    test('co_pilot preset rejects user_configurable.trusted_domains: true',
        () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'preset': 'co_pilot',
          'user_configurable': <String, dynamic>{'trusted_domains': true},
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('trusted_domains'),
        )),
      );
    });

    test('browser preset accepts user_configurable.home_url and trusted_domains',
        () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'preset': 'browser',
        'user_configurable': <String, dynamic>{
          'home_url': true,
          'trusted_domains': true,
        },
      });
      expect(c.preset, 'browser');
      expect(c.userConfigurable.homeUrl, isTrue);
      expect(c.userConfigurable.trustedDomains, isTrue);
    });

    test('rejects byok.providers entries not in the allowed set', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'byok': <String, dynamic>{
            'providers': <String>['anthropic', 'pineapple'],
          },
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('pineapple'),
        )),
      );
    });

    test('rejects byok.default_provider not in byok.providers', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'byok': <String, dynamic>{
            'providers': <String>['anthropic'],
            'default_provider': 'google',
          },
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('default_provider'),
        )),
      );
    });

    test('rejects billing.mode outside allowed set', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'billing': <String, dynamic>{'mode': 'mystery'},
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          contains('ai.billing.mode'),
        )),
      );
    });

    test('rejects billing.mode: managed in v1 with clear message', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'billing': <String, dynamic>{'mode': 'managed'},
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          allOf(contains('managed'), contains('v1')),
        )),
      );
    });

    test('rejects billing.mode: local in v1 with clear message', () {
      expect(
        () => AiConfig.fromMap(<String, dynamic>{
          'billing': <String, dynamic>{'mode': 'local'},
        }),
        throwsA(isA<AiConfigError>().having(
          (e) => e.message,
          'message',
          allOf(contains('local'), contains('v2')),
        )),
      );
    });
  });

  group('AiConfigError', () {
    test('toString includes the message', () {
      final err = AiConfigError('something exploded');
      expect(err.toString(), contains('AiConfigError'));
      expect(err.toString(), contains('something exploded'));
    });
  });

  group('Sub-config defaults — direct construction', () {
    test('UserConfigurableConfig.defaults', () {
      final c = UserConfigurableConfig.defaults();
      expect(c.homeUrl, isFalse);
      expect(c.autonomy, isTrue);
    });

    test('ByokConfig.defaults', () {
      final c = ByokConfig.defaults();
      expect(c.embeddingsProvider, 'voyage');
    });

    test('NavigationPolicyConfig.defaults', () {
      final c = NavigationPolicyConfig.defaults();
      expect(c.untrustedAction, 'prompt');
      expect(c.logAllNavigations, isTrue);
    });

    test('ActionDefaultsConfig.defaults', () {
      final c = ActionDefaultsConfig.defaults();
      expect(c.pageInteractions, 'auto');
      expect(c.crossHostNavigation, 'confirm');
    });

    test('DockConfig.defaults', () {
      final c = DockConfig.defaults();
      expect(c.initialPosition, 'bottom_right');
    });

    test('BudgetsConfig.defaults', () {
      final c = BudgetsConfig.defaults();
      expect(c.hardTokenLimitPerTask, 100000);
    });

    test('PageReaderConfig.defaults', () {
      final c = PageReaderConfig.defaults();
      expect(c.setOfMarks, isTrue);
    });

    test('MemoryRouterConfig.defaults', () {
      final c = MemoryRouterConfig.defaults();
      expect(c.strategy, 'heuristic');
    });

    test('MemoryRetentionConfig.defaults', () {
      final c = MemoryRetentionConfig.defaults();
      expect(c.episodicDays, 0);
    });

    test('SecurityConfig.defaults', () {
      final c = SecurityConfig.defaults();
      expect(c.classifierMode, 'edge_preferred');
    });

    test('ParaphraseConfig.defaults', () {
      final c = ParaphraseConfig.defaults();
      expect(c.enabled, isFalse);
      expect(c.onClassifierFlag, isTrue);
    });

    test('ParaphraseCloudFallbackModelConfig.defaults', () {
      final c = ParaphraseCloudFallbackModelConfig.defaults();
      expect(c.provider, 'anthropic');
      expect(c.model, 'claude-haiku-4-5');
    });

    test('EdgeDefenseConfig.defaults', () {
      final c = EdgeDefenseConfig.defaults();
      expect(c.mode, 'auto');
      expect(c.downloadStrategy, 'lazy');
    });

    test('BillingByokConfig.defaults', () {
      final c = BillingByokConfig.defaults();
      expect(c.providers, isEmpty);
    });

    test('BillingManagedConfig.defaults', () {
      final c = BillingManagedConfig.defaults();
      expect(c.proxyEndpoint, '');
      expect(c.freeTrialCredits, 100);
    });

    test('BillingLocalConfig.defaults', () {
      final c = BillingLocalConfig.defaults();
      expect(c.requireTier, 'A+');
    });

    test('RouterClassifierConfig.defaults', () {
      final c = RouterClassifierConfig.defaults();
      expect(c.mode, 'heuristic');
    });

    test('RouterOverridesConfig.defaults', () {
      final c = RouterOverridesConfig.defaults();
      expect(c.routine, isNull);
      expect(c.reasoning, isNull);
      expect(c.heavy, isNull);
    });
  });

  group('Type coercion', () {
    test('int fields tolerate num (double) inputs', () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'budgets': <String, dynamic>{
          'soft_token_limit_per_task': 12345.0,
        },
      });
      expect(c.budgets.softTokenLimitPerTask, 12345);
    });

    test('list fields reject non-string entries', () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'navigation_policy': <String, dynamic>{
          'trusted_domains': <dynamic>['*.example.com', 42, null, 'ok.test'],
        },
      });
      expect(
        c.navigationPolicy.trustedDomains,
        ['*.example.com', 'ok.test'],
      );
    });

    test('map fields reject non-string entries', () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'autonomy': <String, dynamic>{
          'per_host_overrides': <dynamic, dynamic>{
            'host.example.com': 'trusted',
            123: 'ignored',
            'bad.example.com': 99,
          },
        },
      });
      expect(
        c.autonomy.perHostOverrides,
        <String, String>{'host.example.com': 'trusted'},
      );
    });

    test('preset list ignores non-map entries', () {
      final c = AiConfig.fromMap(<String, dynamic>{
        'presets': <dynamic>[
          <String, dynamic>{'name': 'A', 'home_url': 'https://a.test'},
          'not-a-map',
          42,
        ],
      });
      expect(c.presets, hasLength(1));
      expect(c.presets.first.name, 'A');
    });
  });
}

/// The canonical `ai:` block from `docs/AI_DESIGN.md` §10, used to verify
/// round-trip parsing for every documented key path.
Map<String, dynamic> _canonicalAiBlock() => <String, dynamic>{
      'enabled': true,
      'preset': 'co_pilot',
      'user_configurable': <String, dynamic>{
        'home_url': false,
        'trusted_domains': false,
        'autonomy': true,
        'require_validation': true,
      },
      'presets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Hacker News',
          'home_url': 'https://news.ycombinator.com',
          'trusted_domains': <String>['*.ycombinator.com'],
        },
      ],
      'byok': <String, dynamic>{
        'required': true,
        'providers': <String>['anthropic', 'openai', 'google'],
        'default_provider': 'anthropic',
        'default_model': <String, String>{
          'anthropic': 'claude-opus-4-7',
          'openai': 'gpt-5',
          'google': 'gemini-2.5-pro',
        },
        'embeddings_provider': 'voyage',
      },
      'navigation_policy': <String, dynamic>{
        'home_only': false,
        'trusted_domains': <String>[],
        'untrusted_action': 'prompt',
        'log_all_navigations': true,
      },
      'autonomy': <String, dynamic>{
        'action_defaults': <String, dynamic>{
          'page_interactions': 'auto',
          'cross_host_navigation': 'confirm',
          'form_submits': 'confirm',
          'native_actions': 'confirm',
        },
        'per_host_overrides': <String, String>{},
      },
      'dock': <String, dynamic>{
        'enabled': true,
        'initial_position': 'bottom_right',
        'hideable': true,
        'show_on_first_launch': true,
      },
      'budgets': <String, dynamic>{
        'soft_token_limit_per_task': 50000,
        'hard_token_limit_per_task': 100000,
        'soft_step_threshold': 30,
        'monthly_token_warning': 5000000,
      },
      'page_reader': <String, dynamic>{
        'dom_digest': true,
        'screenshot_on_request': true,
        'set_of_marks': true,
        'diff_subsequent_turns': true,
        'perceptual_hash_dedup': true,
      },
      'memory': <String, dynamic>{
        'core_enabled': true,
        'episodic_enabled': true,
        'semantic_enabled': true,
        'resource_enabled': false,
        'procedural_enabled': false,
        'audit_log_enabled': true,
        'embeddings_enabled': true,
        'auto_extract_enabled': true,
        'router': <String, dynamic>{
          'strategy': 'heuristic',
          'escalate_on_ambiguity': true,
        },
        'retention': <String, dynamic>{
          'episodic_days': 0,
          'max_episodic_rows': 100000,
        },
      },
      'privacy': <String, dynamic>{
        'crash_reporting': 'ask_at_onboarding',
        'anonymous_usage_telemetry': false,
      },
      'security': <String, dynamic>{
        'sanitization_enabled': true,
        'spotlighting_enabled': true,
        'classifier_mode': 'edge_preferred',
        'paraphrase': <String, dynamic>{
          'enabled': false,
          'high_risk_hosts': <String>[],
          'on_classifier_flag': true,
          'execution': 'edge_preferred',
          'cloud_fallback_model': <String, dynamic>{
            'provider': 'anthropic',
            'model': 'claude-haiku-4-5',
          },
        },
        'self_reflect_enabled': true,
        'self_reflect_execution': 'edge_preferred',
      },
      'edge_defense': <String, dynamic>{
        'mode': 'auto',
        'download_strategy': 'lazy',
        'fallback_on_quota': true,
        'show_quota_indicator': 'near_exhaustion',
      },
      'billing': <String, dynamic>{
        'mode': 'byok',
        'byok': <String, dynamic>{
          'providers': <String, dynamic>{
            'anthropic': <String, dynamic>{
              'recommended': true,
              'security_posture':
                  'Adversarial training in place; recommended.',
              'supported_models': <String>[
                'claude-opus-4-7',
                'claude-sonnet-4-6',
                'claude-haiku-4-5',
              ],
            },
          },
        },
        'managed': <String, dynamic>{
          'proxy_endpoint': '',
          'free_trial_credits': 100,
        },
        'local': <String, dynamic>{'require_tier': 'A+'},
      },
      'router': <String, dynamic>{
        'preset': 'balanced',
        'show_routing_badge': true,
        'classifier': <String, dynamic>{'mode': 'heuristic'},
        'overrides': <String, dynamic>{
          'routine': null,
          'reasoning': null,
          'heavy': null,
        },
        'cross_provider_overrides_allowed': true,
        'tier_mapping': <String, dynamic>{
          'anthropic': <String, String>{
            'routine': 'claude-haiku-4-5',
            'reasoning': 'claude-sonnet-4-6',
            'heavy': 'claude-opus-4-7',
          },
          'openai': <String, String>{
            'routine': 'gpt-5-nano',
            'reasoning': 'gpt-5-mini',
            'heavy': 'gpt-5',
          },
          'google': <String, String>{
            'routine': 'gemini-flash',
            'reasoning': 'gemini-2.5-pro',
            'heavy': 'gemini-2.5-pro-thinking',
          },
        },
      },
    };
