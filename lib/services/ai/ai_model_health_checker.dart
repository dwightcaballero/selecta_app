import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum AiModelStatus { ok, notFound, authError, unreachable }

class AiModelCheckResult {
  final AiModelStatus status;
  final String message;

  const AiModelCheckResult(this.status, this.message);

  bool get isOk => status == AiModelStatus.ok;
}

/// Verifies that a configured model is still served by its provider.
class AiModelHealthChecker {
  final http.Client _client;
  final Duration timeout;

  AiModelHealthChecker({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  /// Gemini's model metadata endpoint still lists retired models, so a minimal
  /// generateContent call is the only reliable availability probe.
  Future<AiModelCheckResult> checkGemini(String apiKey, String model) async {
    final key = apiKey.trim();
    final name = model.trim();
    if (key.isEmpty) return const AiModelCheckResult(AiModelStatus.authError, 'Enter a Gemini API key to verify the model.');
    if (name.isEmpty) return const AiModelCheckResult(AiModelStatus.notFound, 'Model name is empty.');

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$name:generateContent?key=$key',
    );
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'ping'},
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 16},
            }),
          )
          .timeout(timeout);
      return _interpret(response, name);
    } on TimeoutException {
      return const AiModelCheckResult(AiModelStatus.unreachable, 'Timed out while contacting Gemini.');
    } catch (e) {
      return AiModelCheckResult(AiModelStatus.unreachable, 'Could not reach Gemini: $e');
    }
  }

  Future<AiModelCheckResult> checkGroq(String apiKey, String model) async {
    final key = apiKey.trim();
    final name = model.trim();
    if (key.isEmpty) return const AiModelCheckResult(AiModelStatus.authError, 'Enter a Groq API key to verify the model.');
    if (name.isEmpty) return const AiModelCheckResult(AiModelStatus.notFound, 'Model name is empty.');

    final uri = Uri.parse('https://api.groq.com/openai/v1/models/$name');
    try {
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $key'})
          .timeout(timeout);
      final result = _interpret(response, name);
      if (result.isOk) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['active'] == false) {
            return AiModelCheckResult(AiModelStatus.notFound, 'Model "$name" is no longer active on Groq.');
          }
        } catch (_) {}
      }
      return result;
    } on TimeoutException {
      return const AiModelCheckResult(AiModelStatus.unreachable, 'Timed out while contacting Groq.');
    } catch (e) {
      return AiModelCheckResult(AiModelStatus.unreachable, 'Could not reach Groq: $e');
    }
  }

  AiModelCheckResult _interpret(http.Response response, String model) {
    final code = response.statusCode;
    if (code == 200) return AiModelCheckResult(AiModelStatus.ok, 'Model "$model" is available.');
    // Rate limited means the model exists and the key works.
    if (code == 429) return AiModelCheckResult(AiModelStatus.ok, 'Model "$model" is available (rate limited right now).');
    if (code == 404) {
      return AiModelCheckResult(
        AiModelStatus.notFound,
        'Model "$model" is retired or unavailable. ${_errorMessage(response)}',
      );
    }
    if (code == 401 || code == 403 || (code == 400 && response.body.contains('API key not valid'))) {
      return AiModelCheckResult(AiModelStatus.authError, 'API key was rejected. ${_errorMessage(response)}');
    }
    return AiModelCheckResult(AiModelStatus.unreachable, 'Unexpected response (HTTP $code). ${_errorMessage(response)}');
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error']['message'] ?? '').toString();
      }
    } catch (_) {}
    return '';
  }
}
