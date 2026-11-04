import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selecta_ops/services/ai/ai_model_health_checker.dart';
import 'package:selecta_ops/services/ai/ai_provider_chain.dart';
import 'package:selecta_ops/services/ai/gemini_text_provider.dart';
import 'package:selecta_ops/services/ai/groq_text_provider.dart';
import 'package:selecta_ops/services/ai/text_llm_provider.dart';

class _RetiredModelProvider implements TextLlmProvider {
  int calls = 0;

  @override
  String get id => 'gemini';
  @override
  String get displayName => 'Retired';
  @override
  bool get isConfigured => true;

  @override
  Future<String> generateJson(String prompt, {String? schemaHint, Duration timeout = const Duration(seconds: 15)}) async {
    calls++;
    throw AiProviderException(providerId: id, statusCode: 404, message: 'gone', isModelNotFound: true);
  }

  @override
  Future<String> chat(List<Map<String, String>> messages, {String? systemPrompt, Duration timeout = const Duration(seconds: 20)}) async {
    calls++;
    throw AiProviderException(providerId: id, statusCode: 404, message: 'gone', isModelNotFound: true);
  }
}

class _OkProvider implements TextLlmProvider {
  @override
  String get id => 'groq';
  @override
  String get displayName => 'Ok';
  @override
  bool get isConfigured => true;

  @override
  Future<String> generateJson(String prompt, {String? schemaHint, Duration timeout = const Duration(seconds: 15)}) async => '{"ok":true}';

  @override
  Future<String> chat(List<Map<String, String>> messages, {String? systemPrompt, Duration timeout = const Duration(seconds: 20)}) async => 'hi';
}

http.Response _json(int code, Object body) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  group('Providers flag retired models', () {
    test('Gemini 404 throws isModelNotFound with actionable message', () async {
      final provider = GeminiTextProvider(
        getApiKey: () => 'k',
        model: 'gemini-2.0-flash',
        client: MockClient((_) async => _json(404, {
              'error': {'code': 404, 'message': 'This model is no longer available.', 'status': 'NOT_FOUND'},
            })),
      );
      try {
        await provider.generateJson('x');
        fail('expected exception');
      } on AiProviderException catch (e) {
        expect(e.isModelNotFound, isTrue);
        expect(e.message, contains('gemini-2.0-flash'));
        expect(e.message, contains('Superadmin'));
      }
    });

    test('Groq model_not_found throws isModelNotFound on chat and generateJson', () async {
      final provider = GroqTextProvider(
        getApiKey: () => 'k',
        model: 'llama-3.3-70b-versatile',
        client: MockClient((_) async => _json(404, {
              'error': {'message': 'The model does not exist', 'code': 'model_not_found'},
            })),
      );
      for (final call in [
        () => provider.generateJson('x'),
        () => provider.chat([
              {'role': 'user', 'content': 'x'},
            ]),
      ]) {
        try {
          await call();
          fail('expected exception');
        } on AiProviderException catch (e) {
          expect(e.isModelNotFound, isTrue);
          expect(e.isAuthError, isFalse);
        }
      }
    });
  });

  group('AiProviderChain with retired model', () {
    test('skips provider for the cooldown, falls back, and reports once', () async {
      final retired = _RetiredModelProvider();
      final chain = AiProviderChain(providers: [retired, _OkProvider()]);
      final reports = <String>[];
      chain.onModelNotFound = (id, message) => reports.add(id);

      expect(await chain.generateJson('x'), '{"ok":true}');
      expect(await chain.generateJson('x'), '{"ok":true}');

      expect(retired.calls, 1);
      expect(reports, ['gemini']);
      expect(chain.getCircuitState('gemini').isOpen(), isTrue);
    });
  });

  group('AiModelHealthChecker', () {
    test('Gemini: 200 is ok, 404 is notFound, 400 invalid key is authError, 429 still ok', () async {
      Future<AiModelCheckResult> run(http.Response res) =>
          AiModelHealthChecker(client: MockClient((_) async => res)).checkGemini('k', 'm');

      expect((await run(_json(200, {'candidates': []}))).status, AiModelStatus.ok);
      expect((await run(_json(404, {'error': {'message': 'retired'}}))).status, AiModelStatus.notFound);
      expect((await run(_json(400, {'error': {'message': 'API key not valid. Please pass a valid API key.'}}))).status,
          AiModelStatus.authError);
      expect((await run(_json(429, {'error': {'message': 'quota'}}))).status, AiModelStatus.ok);
      expect((await run(_json(503, {'error': {'message': 'busy'}}))).status, AiModelStatus.unreachable);
    });

    test('Groq: inactive model counts as notFound; 401 is authError', () async {
      Future<AiModelCheckResult> run(http.Response res) =>
          AiModelHealthChecker(client: MockClient((_) async => res)).checkGroq('k', 'm');

      expect((await run(_json(200, {'id': 'm', 'active': true}))).status, AiModelStatus.ok);
      expect((await run(_json(200, {'id': 'm', 'active': false}))).status, AiModelStatus.notFound);
      expect((await run(_json(404, {'error': {'message': 'does not exist'}}))).status, AiModelStatus.notFound);
      expect((await run(_json(401, {'error': {'message': 'Invalid API Key'}}))).status, AiModelStatus.authError);
    });

    test('empty key or model short-circuits without a network call', () async {
      var calls = 0;
      final checker = AiModelHealthChecker(client: MockClient((_) async {
        calls++;
        return _json(200, {});
      }));
      expect((await checker.checkGemini('', 'm')).status, AiModelStatus.authError);
      expect((await checker.checkGroq('k', ' ')).status, AiModelStatus.notFound);
      expect(calls, 0);
    });
  });
}
