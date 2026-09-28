import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/services/configuration_service.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

/// Result status when verifying if AI operations are allowed.
class AiStatusCheck {
  final bool isAllowed;
  final String? message;
  final int currentUsage;
  final int limit;

  AiStatusCheck({
    required this.isAllowed,
    this.message,
    this.currentUsage = 0,
    this.limit = 1000,
  });
}

/// Service managing communication with the Google Gemini API for Selecta operations,
/// including remote key fetching, master enable/disable, and quota tracking/enforcement.
class GeminiAiService {
  static const List<String> _candidateModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-flash-latest',
  ];
  static const String _usageCollection = 'ai_usage_metrics';
  static const String defaultApiKey = '';

  final ConfigurationService _configService = ConfigurationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _activeModelIndex = 0;
  GenerativeModel? _model;
  ChatSession? _chatSession;
  String? _cachedApiKey;
  String? _cachedContextPrompt;

  static final GeminiAiService _instance = GeminiAiService._internal();
  factory GeminiAiService() => _instance;
  GeminiAiService._internal();

  /// Gets the current month key for quota tracking (e.g. "2026-09").
  String get _currentMonthKey => DateFormat('yyyy-MM').format(DateTime.now());

  /// Checks if AI is enabled and whether quota has not been exceeded.
  Future<AiStatusCheck> checkAiAvailability() async {
    final config = await _configService.getConfiguration();

    // 1. Check if disabled globally
    if (!config.aiEnabled) {
      return AiStatusCheck(
        isAllowed: false,
        message: 'The AI Assistant is currently disabled by your Administrator.',
      );
    }

    // 2. Check if API key is configured
    final apiKey = await getEffectiveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return AiStatusCheck(
        isAllowed: false,
        message: 'AI Assistant is not configured yet. Please configure the Gemini Key in Configurations.',
      );
    }

    // 3. Check monthly quota usage in Firestore
    final currentUsage = await getCurrentMonthUsage();
    final limit = config.aiMonthlyRequestLimit;

    if (limit > 0 && currentUsage >= limit) {
      return AiStatusCheck(
        isAllowed: false,
        currentUsage: currentUsage,
        limit: limit,
        message: 'Monthly AI quota limit reached ($currentUsage / $limit calls). '
            'The AI Assistant is paused to prevent unexpected costs.',
      );
    }

    // Warning zone: 90% quota reached
    if (limit > 0 && currentUsage >= (limit * 0.90).floor()) {
      return AiStatusCheck(
        isAllowed: true,
        currentUsage: currentUsage,
        limit: limit,
        message: '⚠️ Quota Alert: $currentUsage of $limit monthly requests used (~${((currentUsage / limit) * 100).toStringAsFixed(0)}%).',
      );
    }

    return AiStatusCheck(
      isAllowed: true,
      currentUsage: currentUsage,
      limit: limit,
    );
  }

  /// Returns the current monthly usage count.
  Future<int> getCurrentMonthUsage() async {
    try {
      final doc = await _firestore.collection(_usageCollection).doc(_currentMonthKey).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['requestCount'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Increments the monthly AI usage counter in Firestore.
  Future<void> recordAiUsage() async {
    try {
      final docRef = _firestore.collection(_usageCollection).doc(_currentMonthKey);
      await docRef.set({
        'requestCount': FieldValue.increment(1),
        'lastUsed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Retrieves the active API key. First checks remote shared configuration (Firestore),
  /// falling back to compile-time env (--dart-define=GEMINI_API_KEY).
  Future<String?> getEffectiveApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey;
    }

    // 1. Fetch from Firestore shared configuration (so 1 key works for all users)
    try {
      final config = await _configService.getConfiguration();
      if (config.geminiApiKey.isNotEmpty) {
        _cachedApiKey = config.geminiApiKey.trim();
        return _cachedApiKey;
      }
    } catch (_) {}

    // 2. Fallback: check compile-time environment variable
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) {
      _cachedApiKey = envKey;
      return envKey;
    }

    // 3. Fallback: pre-configured developer key
    if (defaultApiKey.isNotEmpty) {
      _cachedApiKey = defaultApiKey;
      return defaultApiKey;
    }

    return null;
  }

  void invalidateCachedKey() {
    _cachedApiKey = null;
    _model = null;
    _chatSession = null;
  }

  /// Initializes or re-initializes the generative model with system instructions.
  Future<GenerativeModel?> getModel({String? contextPrompt, int? modelIndex}) async {
    final key = await getEffectiveApiKey();
    if (key == null || key.isEmpty) return null;

    final targetIndex = modelIndex ?? _activeModelIndex;
    final modelName = _candidateModels[targetIndex % _candidateModels.length];

    final systemInstruction = Content.system(
      'You are Sedy, an intelligent operations AI assistant embedded directly inside the Selecta Distribution & Sales mobile app. '
      'Your role is to assist Selecta dealers and salesmen with daily sales, delivery tracking, store visits (PJP - Permanent Journey Plan), '
      'bad order inspections, Merch Blitz campaigns, throughput goals, and expenses.\n\n'
      'Formatting and readability rules for mobile screens:\n'
      '- Make generous use of newlines, empty lines, and indents to keep responses airy and effortless to read.\n'
      '- NEVER cram multiple metrics or distinct ideas into one long sentence or dense paragraph.\n'
      '- NEVER cram multiple attributes onto the same line separated by pipes (do NOT do: "Target: X | Actual: Y"). Put each attribute on its own indented line.\n'
      '- NEVER use Markdown tables (e.g. | Col 1 | Col 2 |). Mobile screens are narrow, and tables cause horizontal scrolling and confusion.\n'
      '- Use bold text for key figures, metrics, and amounts (e.g. **₱12,500.00**, **4 Pending Deliveries**).\n'
      '- When presenting lists of stores, products, or breakdowns, format each as a clean vertical card with indented attributes (using Markdown list bullets "- ") and an empty line between cards:\n'
      '  Example format:\n'
      '  🏪 **7-Eleven Bayanihan**\n'
      '  - **Target**: ₱15,000\n'
      '  - **Actual Sales**: ₱16,200 (+8%)\n'
      '  - **Status**: ✅ Hit Target\n'
      '    - **PJP Visit**: Visited\n\n'
      '  🏪 **Mini Stop Poblacion**\n'
      '  - **Target**: ₱12,000\n'
      '  - **Actual Sales**: ₱9,500 (-21%)\n'
      '  - **Status**: ⚠️ Needs Follow-up\n\n'
      '- For KPI summaries or operational updates, group by topic with a short bold header and separate each metric on its own indented line:\n'
      '  📊 **Sales Overview**\n'
      '  - **Total Buying Sales**: ₱125,000\n'
      '  - **Buying Throughput**: 82%\n\n'
      '  🚚 **Deliveries**\n'
      '  - **Pending Deliveries**: 4 orders\n'
      '  - **Returned**: 1 order\n\n'
      '- Separate paragraphs, sections, and card blocks with a full blank line.\n'
      '- At the end of every helpful response, provide 2 or 3 quick suggested follow-up questions under a line starting with: "💡 Suggested questions:" with bullet points so the user can easily tap to explore further.'
      '${contextPrompt != null ? "\n\nCurrent operational context:\n$contextPrompt" : ""}',
    );

    _model = GenerativeModel(
      model: modelName,
      apiKey: key,
      systemInstruction: systemInstruction,
    );

    return _model;
  }

  /// Starts a fresh multi-turn chat session with operational context.
  Future<ChatSession?> startChat({String? contextPrompt}) async {
    _cachedContextPrompt = contextPrompt;
    final model = await getModel(contextPrompt: contextPrompt, modelIndex: _activeModelIndex);
    if (model == null) return null;
    _chatSession = model.startChat();
    return _chatSession;
  }

  bool _isOverloadedError(dynamic e) {
    final errStr = e.toString().toLowerCase();
    return errStr.contains('high demand') ||
        errStr.contains('overloaded') ||
        errStr.contains('503') ||
        errStr.contains('resourceexhausted') ||
        errStr.contains('try again later');
  }

  /// Sends a message in the active chat session after validating quota,
  /// with transparent fallback and retry across candidate models on high demand.
  Future<String> sendMessage(String userMessage) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }

    if (_chatSession == null) {
      await startChat(contextPrompt: _cachedContextPrompt);
    }

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        if (_chatSession == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final response = await _chatSession!.sendMessage(Content.text(userMessage));
        await recordAiUsage();
        return response.text ?? 'No response received from Gemini.';
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          // Failover to next candidate model
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          await startChat(contextPrompt: _cachedContextPrompt);
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please tap send again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Unable to reach Google Gemini. Please try again.');
  }

  /// Single-turn prompt generation with automatic failover.
  Future<String> generateText(String prompt, {String? contextPrompt}) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(contextPrompt: contextPrompt, modelIndex: _activeModelIndex);
        if (model == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final response = await model.generateContent([Content.text(prompt)]);
        await recordAiUsage();
        return response.text ?? 'No response generated.';
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Unable to generate response. Please try again.');
  }
}
