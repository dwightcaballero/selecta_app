import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';

void main() {
  group('GeminiAiService Retry & Backoff Unit Tests', () {
    final aiService = GeminiAiService();

    test('isRetryableError identifies 429, 503, and rate limit errors', () {
      expect(aiService.isRetryableError(Exception('Error 429: Too Many Requests')), isTrue);
      expect(aiService.isRetryableError(Exception('503 Service Unavailable')), isTrue);
      expect(aiService.isRetryableError(Exception('ResourceExhausted: Quota exceeded')), isTrue);
      expect(aiService.isRetryableError(Exception('Google Gemini servers overloaded')), isTrue);
      expect(aiService.isRetryableError(Exception('high demand, please try again later')), isTrue);
      expect(aiService.isRetryableError(Exception('rate limit exceeded')), isTrue);
    });

    test('isRetryableError identifies spotty network errors', () {
      expect(aiService.isRetryableError(Exception('SocketException: OS Error: Connection reset by peer')), isTrue);
      expect(aiService.isRetryableError(Exception('TimeoutException after 0:00:30.000000')), isTrue);
      expect(aiService.isRetryableError(Exception('ClientException: Connection closed before full header was received')), isTrue);
      expect(aiService.isRetryableError(Exception('HandshakeException: Connection terminated')), isTrue);
    });

    test('isRetryableError rejects unrelated fatal errors', () {
      expect(aiService.isRetryableError(Exception('Invalid API Key provided')), isFalse);
      expect(aiService.isRetryableError(FormatException('Invalid JSON')), isFalse);
    });

    test('notifyRetryForTesting triggers onRetryNotification with exact user reassurance message', () {
      String? capturedMessage;
      GeminiAiService.onRetryNotification = (msg) {
        capturedMessage = msg;
      };

      aiService.notifyRetryForTesting(2, 3);
      expect(capturedMessage, equals('Network slowed down — retrying (attempt 2 of 3)...'));

      aiService.notifyRetryForTesting(3, 3);
      expect(capturedMessage, equals('Network slowed down — retrying (attempt 3 of 3)...'));

      GeminiAiService.onRetryNotification = null;
    });

    testWidgets('SnackBarWidget.showRetryToast displays visual toast via rootScaffoldMessengerKey', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: const Scaffold(
            body: Center(child: Text('App Home')),
          ),
        ),
      );

      SnackBarWidget.showRetryToast('Network slowed down — retrying (attempt 2 of 3)...');
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 300)); // Complete entry animation

      expect(find.text('Network slowed down — retrying (attempt 2 of 3)...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
