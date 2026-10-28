import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/ai/ai_provider_chain.dart';
import 'package:selecta_ops/services/ai/text_llm_provider.dart';

class FakeTextProvider implements TextLlmProvider {
  @override
  final String id;
  @override
  final String displayName;
  @override
  bool isConfigured;

  int generateJsonCallCount = 0;
  int chatCallCount = 0;
  bool shouldThrowRateLimit = false;
  bool shouldThrowAuth = false;
  String jsonResponse = '{"status": "ok"}';
  String chatResponse = 'Hello from fake';

  FakeTextProvider({
    required this.id,
    required this.displayName,
    this.isConfigured = true,
  });

  @override
  Future<String> generateJson(
    String prompt, {
    String? schemaHint,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    generateJsonCallCount++;
    if (shouldThrowRateLimit) {
      throw AiProviderException(
        providerId: id,
        statusCode: 429,
        message: 'Rate limit hit',
        isRateLimit: true,
        retryAfter: const Duration(seconds: 1),
      );
    }
    if (shouldThrowAuth) {
      throw AiProviderException(
        providerId: id,
        statusCode: 401,
        message: 'Invalid key',
        isAuthError: true,
      );
    }
    return jsonResponse;
  }

  @override
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    chatCallCount++;
    if (shouldThrowRateLimit) {
      throw AiProviderException(
        providerId: id,
        statusCode: 429,
        message: 'Rate limit hit',
        isRateLimit: true,
      );
    }
    return chatResponse;
  }
}

void main() {
  group('AiProviderChain Unit Tests', () {
    late FakeTextProvider gemini;
    late FakeTextProvider groq;
    late AiProviderChain chain;

    setUp(() {
      gemini = FakeTextProvider(id: 'gemini', displayName: 'Gemini');
      groq = FakeTextProvider(id: 'groq', displayName: 'Groq');
      chain = AiProviderChain(providers: [gemini, groq]);
    });

    test('Primary provider handles generateJson successfully', () async {
      final res = await chain.generateJson('Extract items');
      expect(res, equals('{"status": "ok"}'));
      expect(gemini.generateJsonCallCount, equals(1));
      expect(groq.generateJsonCallCount, equals(0));
      expect(chain.lastUsedProviderId, equals('gemini'));
    });

    test('Falls back to secondary provider when primary hits rate limit', () async {
      gemini.shouldThrowRateLimit = true;
      groq.jsonResponse = '{"source": "groq"}';

      final res = await chain.generateJson('Extract items');
      expect(res, equals('{"source": "groq"}'));
      expect(gemini.generateJsonCallCount, equals(1));
      expect(groq.generateJsonCallCount, equals(1));
      expect(chain.lastUsedProviderId, equals('groq'));
    });

    test('Circuit breaker skips failed provider on subsequent calls while open', () async {
      gemini.shouldThrowRateLimit = true;
      groq.jsonResponse = '{"source": "groq"}';

      // First call trips gemini circuit
      await chain.generateJson('Call 1');
      expect(gemini.generateJsonCallCount, equals(1));
      expect(groq.generateJsonCallCount, equals(1));

      // Second call should skip gemini directly while circuit is open
      await chain.generateJson('Call 2');
      expect(gemini.generateJsonCallCount, equals(1)); // Did NOT increment!
      expect(groq.generateJsonCallCount, equals(2));
    });

    test('Chat falls back smoothly from Gemini to Groq', () async {
      gemini.shouldThrowRateLimit = true;
      groq.chatResponse = 'Response from Groq assistant';

      final reply = await chain.chat([{'role': 'user', 'content': 'Hi'}]);
      expect(reply, equals('Response from Groq assistant'));
      expect(gemini.chatCallCount, equals(1));
      expect(groq.chatCallCount, equals(1));
    });

    test('Throws AiProviderException if all providers fail or are unconfigured', () async {
      gemini.isConfigured = false;
      groq.shouldThrowRateLimit = true;

      expect(
        () => chain.generateJson('Extract'),
        throwsA(isA<AiProviderException>()),
      );
    });

    test('resolveActiveProvider respects preferred order and skip unconfigured', () {
      gemini.isConfigured = false;
      groq.isConfigured = true;

      final active = chain.resolveActiveProvider(['gemini', 'groq']);
      expect(active?.id, equals('groq'));
    });
  });
}
