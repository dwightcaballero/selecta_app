import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:selecta_ops/services/ai/text_llm_provider.dart';

/// Gemini implementation of [TextLlmProvider] using direct REST endpoints
/// to Google Generative Language API without SDK dependencies.
class GeminiTextProvider implements TextLlmProvider {
  final String Function() getApiKey;
  final String model;
  final http.Client _client;

  GeminiTextProvider({
    required this.getApiKey,
    this.model = 'gemini-2.0-flash',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Google Gemini ($model)';

  @override
  bool get isConfigured => getApiKey().trim().isNotEmpty;

  String _cleanJsonString(String raw) {
    var trimmed = raw.trim();
    if (trimmed.startsWith('```json')) {
      trimmed = trimmed.substring(7);
    } else if (trimmed.startsWith('```')) {
      trimmed = trimmed.substring(3);
    }
    if (trimmed.endsWith('```')) {
      trimmed = trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed.trim();
  }

  @override
  Future<String> generateJson(
    String prompt, {
    String? schemaHint,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final apiKey = getApiKey().trim();
    if (apiKey.isEmpty) {
      throw AiProviderException(
        providerId: id,
        message: 'Gemini API key is not configured.',
        isAuthError: true,
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.0,
        'maxOutputTokens': 8192,
      },
      if (schemaHint != null && schemaHint.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {
              'text':
                  'You are a high-speed data extraction engine for retail operations in the Philippines. '
                  'Output strictly valid JSON matching this requirement: $schemaHint',
            },
          ],
        },
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        _handleError(response);
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw AiProviderException(
          providerId: id,
          statusCode: response.statusCode,
          message: 'Gemini returned no candidates in response.',
        );
      }

      final firstCandidate = candidates.first as Map;
      final content = firstCandidate['content'] as Map?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw AiProviderException(
          providerId: id,
          statusCode: response.statusCode,
          message: 'Gemini candidate contains empty content parts.',
        );
      }

      final rawText = parts.first['text'] as String? ?? '';
      return _cleanJsonString(rawText);
    } on TimeoutException {
      throw AiProviderException(
        providerId: id,
        message: 'Gemini generateJson timed out after ${timeout.inSeconds}s.',
        isOverloaded: true,
      );
    } on AiProviderException {
      rethrow;
    } catch (e) {
      throw AiProviderException(
        providerId: id,
        message: 'Network or parse error calling Gemini API: $e',
      );
    }
  }

  @override
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final apiKey = getApiKey().trim();
    if (apiKey.isEmpty) {
      throw AiProviderException(
        providerId: id,
        message: 'Gemini API key is not configured.',
        isAuthError: true,
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final contents = messages.map((m) {
      final role = (m['role'] == 'assistant' || m['role'] == 'model') ? 'model' : 'user';
      return {
        'role': role,
        'parts': [
          {'text': m['content'] ?? ''},
        ],
      };
    }).toList();

    final requestBody = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 2048,
      },
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        _handleError(response);
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw AiProviderException(
          providerId: id,
          statusCode: response.statusCode,
          message: 'Gemini returned empty candidate list.',
        );
      }

      final firstCandidate = candidates.first as Map;
      final content = firstCandidate['content'] as Map?;
      final parts = content?['parts'] as List?;
      return (parts?.first['text'] as String? ?? '').trim();
    } on TimeoutException {
      throw AiProviderException(
        providerId: id,
        message: 'Gemini chat timed out after ${timeout.inSeconds}s.',
        isOverloaded: true,
      );
    } on AiProviderException {
      rethrow;
    } catch (e) {
      throw AiProviderException(
        providerId: id,
        message: 'Gemini chat request failed: $e',
      );
    }
  }

  void _handleError(http.Response response) {
    final code = response.statusCode;
    Duration? retryAfter;
    final retryHeader = response.headers['retry-after'];
    if (retryHeader != null) {
      final seconds = int.tryParse(retryHeader);
      if (seconds != null) {
        retryAfter = Duration(seconds: seconds);
      }
    }

    String message = 'HTTP $code: ${response.body}';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        message = decoded['error']['message']?.toString() ?? message;
      }
    } catch (_) {}

    final isRateLimit = code == 429;
    final isAuth = code == 401 || code == 403;
    final isOverloaded = code == 503 || code == 500 || code == 504 || message.toLowerCase().contains('high demand');

    throw AiProviderException(
      providerId: id,
      statusCode: code,
      message: message,
      isRateLimit: isRateLimit,
      isAuthError: isAuth,
      isOverloaded: isOverloaded,
      retryAfter: retryAfter,
    );
  }
}
