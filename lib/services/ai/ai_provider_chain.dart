import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/services/ai/text_llm_provider.dart';

/// Circuit breaker state for a specific provider.
class ProviderCircuitState {
  DateTime? openUntil;
  int consecutiveFailures = 0;
  int minuteCallCount = 0;
  DateTime lastMinuteWindow = DateTime.now();
  int dailyCallCount = 0;
  String currentDayKey = '';

  bool isOpen() {
    if (openUntil == null) return false;
    if (DateTime.now().isAfter(openUntil!)) {
      openUntil = null;
      consecutiveFailures = 0;
      return false;
    }
    return true;
  }

  void recordFailure({Duration? duration}) {
    consecutiveFailures++;
    final cooldown = duration ?? Duration(seconds: consecutiveFailures >= 2 ? 60 : 30);
    openUntil = DateTime.now().add(cooldown);
  }

  void recordSuccess() {
    consecutiveFailures = 0;
    openUntil = null;
  }

  void incrementCall() {
    final now = DateTime.now();
    final dayKey = '${now.year}-${now.month}-${now.day}';
    if (dayKey != currentDayKey) {
      currentDayKey = dayKey;
      dailyCallCount = 0;
    }
    dailyCallCount++;

    if (now.difference(lastMinuteWindow).inSeconds >= 60) {
      lastMinuteWindow = now;
      minuteCallCount = 0;
    }
    minuteCallCount++;
  }
}

/// Orchestrates text LLM providers with circuit breaking, graceful fallback,
/// and proactive quota throttling across Gemini, Groq, etc.
class AiProviderChain {
  final Map<String, TextLlmProvider> _providers = {};
  final Map<String, ProviderCircuitState> _circuits = {};

  // Estimated free tier caps (can be conservative)
  final Map<String, int> dailyFreeTierCaps = {
    'gemini': 1200, // ~80% of 1500/day
    'groq': 800,    // ~80% of 1000/day
  };

  final Map<String, int> minuteRateLimits = {
    'gemini': 12,   // ~80% of 15/min
    'groq': 25,     // ~80% of 30/min
  };

  String? lastUsedProviderId;

  AiProviderChain({List<TextLlmProvider>? providers}) {
    if (providers != null) {
      for (final p in providers) {
        registerProvider(p);
      }
    }
  }

  void registerProvider(TextLlmProvider provider) {
    _providers[provider.id] = provider;
    _circuits.putIfAbsent(provider.id, () => ProviderCircuitState());
  }

  TextLlmProvider? getProvider(String id) => _providers[id];

  /// Returns circuit state for a provider (useful for debug UI / tests).
  ProviderCircuitState getCircuitState(String providerId) {
    return _circuits.putIfAbsent(providerId, () => ProviderCircuitState());
  }

  /// Determines the active provider given a priority list of provider IDs.
  TextLlmProvider? resolveActiveProvider(List<String> preferredOrder) {
    for (final id in preferredOrder) {
      final provider = _providers[id];
      if (provider == null || !provider.isConfigured) continue;

      final circuit = _circuits[id];
      if (circuit != null && circuit.isOpen()) continue;

      // Check daily proactive cap
      final dailyCap = dailyFreeTierCaps[id];
      if (dailyCap != null && circuit != null && circuit.dailyCallCount >= dailyCap) {
        debugPrint('AiProviderChain: Provider $id reached proactive daily safety cap (${circuit.dailyCallCount}/$dailyCap). Skipping.');
        continue;
      }

      // Check minute proactive cap
      final minuteCap = minuteRateLimits[id];
      if (minuteCap != null && circuit != null && circuit.minuteCallCount >= minuteCap) {
        debugPrint('AiProviderChain: Provider $id reached proactive minute rate cap (${circuit.minuteCallCount}/$minuteCap). Skipping.');
        continue;
      }

      return provider;
    }

    // Secondary pass: if all candidates are constrained by minute rate limits or closed, return the first configured one
    for (final id in preferredOrder) {
      final provider = _providers[id];
      if (provider != null && provider.isConfigured) {
        return provider;
      }
    }
    return null;
  }

  /// Executes [generateJson] through the provider chain in order of [providerOrder].
  Future<String> generateJson(
    String prompt, {
    String? schemaHint,
    List<String> providerOrder = const ['gemini', 'groq'],
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final List<String> errors = [];

    for (final id in providerOrder) {
      final provider = _providers[id];
      if (provider == null) continue;
      if (!provider.isConfigured) {
        errors.add('$id: not configured');
        continue;
      }

      final circuit = _circuits.putIfAbsent(id, () => ProviderCircuitState());
      if (circuit.isOpen()) {
        errors.add('$id: circuit is open until ${circuit.openUntil}');
        continue;
      }

      try {
        circuit.incrementCall();
        final result = await provider.generateJson(
          prompt,
          schemaHint: schemaHint,
          timeout: timeout,
        );
        circuit.recordSuccess();
        lastUsedProviderId = id;
        return result;
      } on AiProviderException catch (e) {
        errors.add('$id: ${e.message}');
        if (e.isRateLimit || e.isOverloaded) {
          circuit.recordFailure(duration: e.retryAfter);
        }
        debugPrint('AiProviderChain: Provider $id failed: ${e.message}. Trying next provider in chain...');
      } catch (e) {
        errors.add('$id: $e');
        circuit.recordFailure();
        debugPrint('AiProviderChain: Unexpected error from $id: $e. Trying next provider in chain...');
      }
    }

    throw AiProviderException(
      providerId: 'chain',
      message: 'All AI providers in chain failed or are unconfigured. Details: [${errors.join("; ")}]',
    );
  }

  /// Executes [chat] through the provider chain in order of [providerOrder].
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    List<String> providerOrder = const ['gemini', 'groq'],
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final List<String> errors = [];

    for (final id in providerOrder) {
      final provider = _providers[id];
      if (provider == null) continue;
      if (!provider.isConfigured) {
        errors.add('$id: not configured');
        continue;
      }

      final circuit = _circuits.putIfAbsent(id, () => ProviderCircuitState());
      if (circuit.isOpen()) {
        errors.add('$id: circuit is open until ${circuit.openUntil}');
        continue;
      }

      try {
        circuit.incrementCall();
        final result = await provider.chat(
          messages,
          systemPrompt: systemPrompt,
          timeout: timeout,
        );
        circuit.recordSuccess();
        lastUsedProviderId = id;
        return result;
      } on AiProviderException catch (e) {
        errors.add('$id: ${e.message}');
        if (e.isRateLimit || e.isOverloaded) {
          circuit.recordFailure(duration: e.retryAfter);
        }
        debugPrint('AiProviderChain: Provider $id chat failed: ${e.message}. Trying next provider...');
      } catch (e) {
        errors.add('$id: $e');
        circuit.recordFailure();
        debugPrint('AiProviderChain: Unexpected chat error from $id: $e. Trying next provider...');
      }
    }

    throw AiProviderException(
      providerId: 'chain',
      message: 'All AI chat providers failed. Details: [${errors.join("; ")}]',
    );
  }
}
