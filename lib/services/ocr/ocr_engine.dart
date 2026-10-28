import 'dart:typed_data';
import 'package:selecta_ops/services/ocr/ocr_result.dart';

/// Abstract engine contract for optical character recognition.
/// Allows swapping between Google ML Kit (Android/iOS), test fakes,
/// and future desktop OCR engines (e.g. Windows.Media.Ocr / Tesseract).
abstract class OcrEngine {
  /// Whether OCR is supported on the current platform/runtime environment.
  bool get isSupported;

  /// Runs OCR on raw encoded image bytes (JPEG / PNG).
  Future<OcrResult> recognizeBytes(Uint8List imageBytes, {int pageIndex = 0});

  /// Runs OCR across a batch of images concurrently (e.g. 2-3 at a time).
  Future<OcrResult> recognizeMultipleBytes(List<Uint8List> imageBytesList);

  /// Releases resources (recognizer models, caches).
  Future<void> dispose();
}
