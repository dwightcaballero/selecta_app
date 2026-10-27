import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/image_slicing_service.dart';

void main() {
  group('AI Document Scan Speed Optimization Tests', () {
    test('GeminiAiService visionGenerationConfig is configured for fast, deterministic JSON OCR', () {
      final config = GeminiAiService.visionGenerationConfig;
      expect(config.responseMimeType, 'application/json');
      expect(config.temperature, 0.0);
      expect(config.maxOutputTokens, 8192);
    });

    test('GeminiAiService candidateModels uses verified flash models and reasonable visionTimeout', () {
      expect(GeminiAiService.candidateModels, contains('gemini-2.5-flash'));
      expect(GeminiAiService.candidateModels, contains('gemini-2.0-flash'));
      expect(GeminiAiService.candidateModels, contains('gemini-1.5-flash'));
      expect(GeminiAiService.candidateModels, isNot(contains('gemini-3.8-flash')));
      expect(GeminiAiService.visionTimeout, const Duration(seconds: 45));
    });

    test('AiScanTimingTracker tracks telemetry metrics and formats summary correctly', () {
      final tracker = AiScanTimingTracker('TestScanFlow');
      expect(tracker.flowName, 'TestScanFlow');

      tracker.startPreAi();
      tracker.stopPreAi();
      tracker.startAiCall(
        model: 'gemini-2.5-flash',
        attempt: 1,
        promptChars: 3500,
        images: 2,
        bytes: [200000, 250000],
        catalog: 85,
      );

      expect(tracker.modelName, 'gemini-2.5-flash');
      expect(tracker.attemptNumber, 1);
      expect(tracker.promptCharCount, 3500);
      expect(tracker.imageCount, 2);
      expect(tracker.imageBytes, [200000, 250000]);
      expect(tracker.catalogCount, 85);

      tracker.recordSuccess(responseChars: 1200);
      expect(tracker.responseCharCount, 1200);
    });

    test('Helperfunctions.prepareImageBytesForAi downscales images larger than 1600px to <= 1600px JPEG', () async {
      // Create a test image of 2000x1000
      final testImage = img.Image(width: 2000, height: 1000);
      img.fill(testImage, color: img.ColorRgb8(100, 150, 200));
      final testBytes = Uint8List.fromList(img.encodePng(testImage));

      final preparedBytes = await Helperfunctions.prepareImageBytesForAi(testBytes);
      expect(preparedBytes, isNotNull);
      expect(preparedBytes.isNotEmpty, isTrue);

      final decoded = img.decodeImage(preparedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1600));
      expect(decoded.height, lessThanOrEqualTo(1600));
      // First 2 bytes of JPEG are 0xFF, 0xD8
      expect(preparedBytes[0], 0xFF);
      expect(preparedBytes[1], 0xD8);
    });

    test('ImageSlicingService slices tall images (aspectRatio > 2.0) into at most 4 JPEG slices', () async {
      // Create an image that is 800 x 3000 (aspect ratio 3.75, height > 2400)
      final tallImage = img.Image(width: 800, height: 3000);
      img.fill(tallImage, color: img.ColorRgb8(220, 220, 220));
      final tallBytes = Uint8List.fromList(img.encodeJpg(tallImage, quality: 80));

      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(tallBytes);
      expect(slices.length, greaterThan(1));
      expect(slices.length, lessThanOrEqualTo(4));

      for (final slice in slices) {
        expect(slice.isNotEmpty, isTrue);
        // Valid JPEG header
        expect(slice[0], 0xFF);
        expect(slice[1], 0xD8);
        final decoded = img.decodeImage(slice);
        expect(decoded, isNotNull);
        expect(decoded!.width, lessThanOrEqualTo(800));
        expect(decoded.height, lessThanOrEqualTo(1600));
      }
    });

    test('ImageSlicingService does not slice normal aspect ratio image', () async {
      // Normal image 800 x 1000 (aspect ratio 1.25)
      final normalImage = img.Image(width: 800, height: 1000);
      img.fill(normalImage, color: img.ColorRgb8(240, 240, 240));
      final normalBytes = Uint8List.fromList(img.encodeJpg(normalImage, quality: 80));

      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(normalBytes);
      expect(slices.length, 1);
      expect(slices.first, normalBytes);
    });
  });
}
