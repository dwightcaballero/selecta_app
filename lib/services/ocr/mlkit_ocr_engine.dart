import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selecta_ops/services/ocr/ocr_engine.dart';
import 'package:selecta_ops/services/ocr/ocr_result.dart';

/// Production on-device OCR engine powered by Google ML Kit (Latin script model).
/// Provides free, unlimited, offline text recognition for Android and iOS.
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _textRecognizer;
  bool _isDisposed = false;

  MlKitOcrEngine() {
    if (isSupported) {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    }
  }

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  TextRecognizer get _recognizer {
    if (_textRecognizer == null || _isDisposed) {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      _isDisposed = false;
    }
    return _textRecognizer!;
  }

  @override
  Future<OcrResult> recognizeBytes(Uint8List imageBytes, {int pageIndex = 0}) async {
    if (!isSupported) {
      throw UnsupportedError('ML Kit Text Recognition is not supported on this platform.');
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.jpg',
    );

    try {
      await tempFile.writeAsBytes(imageBytes, flush: true);
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await _recognizer.processImage(inputImage);

      final blocks = <OcrBlock>[];
      for (final b in recognizedText.blocks) {
        final lines = <OcrLine>[];
        for (final l in b.lines) {
          final elements = <OcrElement>[];
          for (final e in l.elements) {
            elements.add(
              OcrElement(
                text: e.text,
                boundingBox: e.boundingBox,
                confidence: e.confidence,
              ),
            );
          }
          lines.add(
            OcrLine(
              text: l.text,
              boundingBox: l.boundingBox,
              elements: elements,
              confidence: l.confidence,
              pageIndex: pageIndex,
            ),
          );
        }
        blocks.add(
          OcrBlock(
            text: b.text,
            boundingBox: b.boundingBox,
            lines: lines,
          ),
        );
      }

      final page = OcrPage(
        pageIndex: pageIndex,
        blocks: blocks,
      );

      return OcrResult(pages: [page]);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<OcrResult> recognizeMultipleBytes(List<Uint8List> imageBytesList) async {
    if (!isSupported) {
      throw UnsupportedError('ML Kit Text Recognition is not supported on this platform.');
    }

    // Process images with a concurrency limit of 2 to avoid memory pressure
    final allPages = <OcrPage>[];
    const maxConcurrency = 2;

    for (int i = 0; i < imageBytesList.length; i += maxConcurrency) {
      final chunkEnd = (i + maxConcurrency < imageBytesList.length)
          ? i + maxConcurrency
          : imageBytesList.length;

      final futures = <Future<OcrResult>>[];
      for (int j = i; j < chunkEnd; j++) {
        futures.add(recognizeBytes(imageBytesList[j], pageIndex: j));
      }

      final chunkResults = await Future.wait(futures);
      for (final res in chunkResults) {
        allPages.addAll(res.pages);
      }
    }

    return OcrResult(pages: allPages);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _textRecognizer?.close();
    _textRecognizer = null;
  }
}
