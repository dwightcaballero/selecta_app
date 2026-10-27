import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Background worker function executed in an isolate via [compute].
List<Uint8List> _sliceImageWorker(Map<String, dynamic> params) {
  final Uint8List imageBytes = params['bytes'] as Uint8List;
  final double minAspectRatio = params['minAspectRatio'] as double;
  final int minHeight = params['minHeight'] as int;
  final int maxDimension = params['maxDimension'] as int;
  final int quality = params['quality'] as int;

  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return [imageBytes];

  final int width = decoded.width;
  final int height = decoded.height;

  // If width or height is invalid or not an elongated scrolling screenshot, return original
  if (width <= 0 || height <= 0 || (height / width < minAspectRatio) || height < minHeight) {
    return [imageBytes];
  }

  // Determine slice height and overlap
  // Target around 2 to 4 slices max (capped at 4 per AI scan speed plan)
  final int targetSlices = (height / 2000).ceil().clamp(2, 4);
  int sliceHeight = (height / targetSlices).round() + 180;
  if (sliceHeight > 2400) sliceHeight = 2400;
  const int overlap = 180;
  final int step = sliceHeight - overlap;

  final List<Uint8List> slices = [];

  for (int y = 0; y < height; y += step) {
    final int currentSliceHeight = (y + sliceHeight > height) ? (height - y) : sliceHeight;
    if (currentSliceHeight <= overlap && slices.isNotEmpty) {
      break; // Skip tiny bottom remnant
    }

    img.Image slice = img.copyCrop(
      decoded,
      x: 0,
      y: y,
      width: width,
      height: currentSliceHeight,
    );

    // Bound to maxDimension if wider/taller
    if (slice.width > maxDimension || slice.height > maxDimension) {
      if (slice.width >= slice.height) {
        slice = img.copyResize(slice, width: maxDimension);
      } else {
        slice = img.copyResize(slice, height: maxDimension);
      }
    }

    // Direct JPEG encoding - avoids PNG intermediate entirely
    final compressedJpeg = img.encodeJpg(slice, quality: quality);
    slices.add(Uint8List.fromList(compressedJpeg));

    if (slices.length >= 4) break;
  }

  return slices.isNotEmpty ? slices : [imageBytes];
}

/// Service that automatically detects vertically elongated scrolling screenshots
/// and slices them into standard aspect-ratio chunks with overlap.
///
/// Slices directly to JPEG in a background isolate (capping at 4 slices max)
/// avoiding PNG encoding overhead and ensuring razor-sharp OCR clarity.
class ImageSlicingService {
  /// Analyzes an image and returns multiple sliced chunks if it is a scrolling screenshot,
  /// or returns the original image if slicing is not needed.
  static Future<List<Uint8List>> sliceIfScrollingScreenshot(
    Uint8List imageBytes, {
    double minAspectRatioForSlicing = 2.0,
    int minHeightForSlicing = 2400,
    int maxDimension = 1600,
    int quality = 80,
  }) async {
    try {
      final slices = await compute(_sliceImageWorker, {
        'bytes': imageBytes,
        'minAspectRatio': minAspectRatioForSlicing,
        'minHeight': minHeightForSlicing,
        'maxDimension': maxDimension,
        'quality': quality,
      });

      if (slices.length > 1) {
        debugPrint('ImageSlicingService: Auto-sliced scrolling screenshot into ${slices.length} JPEG chunks.');
      }
      return slices;
    } catch (e) {
      debugPrint('ImageSlicingService error: $e. Falling back to original image.');
      return [imageBytes];
    }
  }
}
