import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:selecta_ops/services/ai/text_llm_provider.dart';

/// Groq implementation of [TextLlmProvider] using OpenAI-compatible REST API
/// (`https://api.groq.com/openai/v1/chat/completions`).
class GroqTextProvider implements TextLlmProvider {
  final String Function() getApiKey;
  final String model;
  final http.Client _client;

  GroqTextProvider({
    required this.getApiKey,
    this.model = 'llama-3.3-70b-versatile',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get id => 'groq';

  @override
  String get displayName => 'Groq ($model)';

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
        message: 'Groq API key is not configured.',
        isAuthError: true,
      );
    }

    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final systemContent = StringBuffer('You are a high-speed data extraction engine for retail operations in the Philippines. Return strictly valid JSON.');
    if (schemaHint != null && schemaHint.isNotEmpty) {
      systemContent.write(' $schemaHint');
    }

    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemContent.toString()},
        {'role': 'user', 'content': prompt},
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.0,
      'max_tokens': 4096,
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        _handleError(response);
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw AiProviderException(
          providerId: id,
          statusCode: response.statusCode,
          message: 'Groq returned no choices in response.',
        );
      }

      final firstChoice = choices.first as Map;
      final message = firstChoice['message'] as Map?;
      final content = message?['content'] as String? ?? '';
      return _cleanJsonString(content);
    } on TimeoutException {
      throw AiProviderException(
        providerId: id,
        message: 'Groq generateJson timed out after ${timeout.inSeconds}s.',
        isOverloaded: true,
      );
    } on AiProviderException {
      rethrow;
    } catch (e) {
      throw AiProviderException(
        providerId: id,
        message: 'Network or parse error calling Groq API: $e',
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
        message: 'Groq API key is not configured.',
        isAuthError: true,
      );
    }

    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final formattedMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      formattedMessages.add({'role': 'system', 'content': systemPrompt});
    }

    for (final m in messages) {
      final role = (m['role'] == 'model' || m['role'] == 'assistant') ? 'assistant' : 'user';
      formattedMessages.add({'role': role, 'content': m['content'] ?? ''});
    }

    final requestBody = {
      'model': model,
      'messages': formattedMessages,
      'temperature': 0.7,
      'max_tokens': 2048,
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        _handleError(response);
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw AiProviderException(
          providerId: id,
          statusCode: response.statusCode,
          message: 'Groq returned no choices in response.',
        );
      }

      final firstChoice = choices.first as Map;
      final message = firstChoice['message'] as Map?;
      return (message?['content'] as String? ?? '').trim();
    } on TimeoutException {
      throw AiProviderException(
        providerId: id,
        message: 'Groq chat timed out after ${timeout.inSeconds}s.',
        isOverloaded: true,
      );
    } on AiProviderException {
      rethrow;
    } catch (e) {
      throw AiProviderException(
        providerId: id,
        message: 'Groq chat request failed: $e',
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
        final err = decoded['error'];
        if (err is Map) {
          message = err['message']?.toString() ?? message;
        } else if (err is String) {
          message = err;
        }
      }
    } catch (_) {}

    final isRateLimit = code == 429;
    final isAuth = code == 401 || code == 403;
    final isOverloaded = code == 503 || code == 500 || code == 504 || message.toLowerCase().contains('overloaded');

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
