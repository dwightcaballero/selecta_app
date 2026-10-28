import 'dart:async';

/// Abstract interface for text-only LLM providers (Gemini, Groq, etc.)
/// operating over pure REST endpoints without heavy client SDKs.
abstract class TextLlmProvider {
  /// Unique identifier (e.g. 'gemini', 'groq').
  String get id;

  /// User-facing display name (e.g. 'Google Gemini Flash', 'Groq Llama 3.3').
  String get displayName;

  /// Whether the provider has an active, valid API key configured.
  bool get isConfigured;

  /// Generates a strict JSON string response from a text prompt.
  /// [schemaHint] is an optional description or JSON schema describing the expected shape.
  Future<String> generateJson(
    String prompt, {
    String? schemaHint,
    Duration timeout = const Duration(seconds: 15),
  });

  /// Generates a chat response given a list of conversation turns.
  /// Each message map typically contains:
  /// - 'role': 'user' | 'model' | 'assistant' | 'system'
  /// - 'content': text content
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 20),
  });
}

/// Custom exception thrown when an AI provider call fails.
class AiProviderException implements Exception {
  final String providerId;
  final int? statusCode;
  final String message;
  final bool isRateLimit;
  final bool isAuthError;
  final bool isOverloaded;
  final Duration? retryAfter;

  AiProviderException({
    required this.providerId,
    required this.message,
    this.statusCode,
    this.isRateLimit = false,
    this.isAuthError = false,
    this.isOverloaded = false,
    this.retryAfter,
  });

  @override
  String toString() => 'AiProviderException($providerId, status: $statusCode): $message';
}
