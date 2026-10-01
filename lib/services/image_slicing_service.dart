import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Service that automatically detects vertically elongated scrolling screenshots
/// and slices them into standard aspect-ratio chunks with overlap.
///
/// This prevents multimodal vision AI models from downscaling long images,
/// ensuring that small text, digits, and quantity columns remain razor sharp.
class ImageSlicingService {
  /// Analyzes an image and returns multiple sliced chunks if it is a scrolling screenshot,
  /// or returns the original image if slicing is not needed.
  static Future<List<Uint8List>> sliceIfScrollingScreenshot(
    Uint8List imageBytes, {
    double minAspectRatioForSlicing = 2.0,
    int minHeightForSlicing = 2400,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final ui.Image fullImage = frame.image;
      final int width = fullImage.width;
      final int height = fullImage.height;

      // If width or height is invalid or not an elongated scrolling screenshot, return original
      if (width <= 0 || height <= 0 || (height / width < minAspectRatioForSlicing) || height < minHeightForSlicing) {
        return [imageBytes];
      }

      // Determine slice height and overlap
      // Target around 2 to 5 slices max, each around 1600-2200 px tall
      int targetSlices = (height / 1800).ceil().clamp(2, 6);
      int sliceHeight = (height / targetSlices).round() + 180;
      if (sliceHeight > 2400) sliceHeight = 2400;
      int overlap = 180;
      int step = sliceHeight - overlap;

      final List<Uint8List> slices = [];

      for (int y = 0; y < height; y += step) {
        final int currentSliceHeight = (y + sliceHeight > height) ? (height - y) : sliceHeight;
        if (currentSliceHeight <= overlap && slices.isNotEmpty) {
          break; // Skip tiny bottom remnant
        }

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(
          recorder,
          Rect.fromLTWH(0, 0, width.toDouble(), currentSliceHeight.toDouble()),
        );

        final srcRect = Rect.fromLTWH(0, y.toDouble(), width.toDouble(), currentSliceHeight.toDouble());
        final dstRect = Rect.fromLTWH(0, 0, width.toDouble(), currentSliceHeight.toDouble());

        canvas.drawImageRect(
          fullImage,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.high,
        );

        final picture = recorder.endRecording();
        final sliceImg = await picture.toImage(width, currentSliceHeight);
        final byteData = await sliceImg.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          slices.add(byteData.buffer.asUint8List());
        }
      }

      if (slices.isNotEmpty) {
        debugPrint('ImageSlicingService: Auto-sliced scrolling screenshot (${width}x$height) into ${slices.length} chunks.');
        return slices;
      }
      return [imageBytes];
    } catch (e) {
      debugPrint('ImageSlicingService error: $e. Falling back to original image.');
      return [imageBytes];
    }
  }
}
