import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/services/ai/gemini_text_provider.dart';
import 'package:selecta_ops/services/ai/groq_text_provider.dart';

void main() {
  group('Text provider model resolution', () {
    test('falls back to defaults when no model is configured', () {
      final gemini = GeminiTextProvider(getApiKey: () => 'k', getModel: () => '');
      final groq = GroqTextProvider(getApiKey: () => 'k');
      expect(gemini.model, GeminiTextProvider.defaultModel);
      expect(groq.model, GroqTextProvider.defaultModel);
    });

    test('getModel is read at call time', () {
      var current = 'gemini-a';
      final gemini = GeminiTextProvider(getApiKey: () => 'k', getModel: () => current);
      expect(gemini.model, 'gemini-a');
      current = 'gemini-b';
      expect(gemini.model, 'gemini-b');
      expect(gemini.displayName, contains('gemini-b'));
    });

    test('explicit model wins over getModel', () {
      final groq = GroqTextProvider(
        getApiKey: () => 'k',
        model: 'explicit/model',
        getModel: () => 'configured/model',
      );
      expect(groq.model, 'explicit/model');
    });
  });

  group('Configuration.fromJson text models', () {
    test('migrates retired model IDs to current defaults', () {
      final config = Configuration.fromJson({
        'textModelGemini': 'gemini-2.0-flash',
        'textModelGroq': 'llama-3.3-70b-versatile',
      });
      expect(config.textModelGemini, GeminiTextProvider.defaultModel);
      expect(config.textModelGroq, GroqTextProvider.defaultModel);
    });

    test('keeps custom model IDs and defaults missing ones', () {
      final custom = Configuration.fromJson({
        'textModelGemini': 'gemini-3.5-flash-lite',
        'textModelGroq': 'qwen/qwen3.8-27b',
      });
      expect(custom.textModelGemini, 'gemini-3.5-flash-lite');
      expect(custom.textModelGroq, 'qwen/qwen3.8-27b');

      final missing = Configuration.fromJson({});
      expect(missing.textModelGemini, GeminiTextProvider.defaultModel);
      expect(missing.textModelGroq, GroqTextProvider.defaultModel);
    });
  });
}
