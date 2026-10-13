import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:selecta_ops/data/helperfunctions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gallery Download Timestamp Adjustment Tests', () {
    test('prepareImageBytesWithCurrentTimestamp injects updated EXIF DateTime tags', () async {
      // 1. Create a baseline image encoded as JPEG
      final sampleImage = img.Image(width: 20, height: 20);
      sampleImage.clear(img.ColorRgb8(100, 150, 200));

      // Set old timestamp (e.g. year 2020)
      sampleImage.exif.imageIfd['DateTime'] = '2020:01:01 12:00:00';
      sampleImage.exif.exifIfd['DateTimeOriginal'] = '2020:01:01 12:00:00';
      sampleImage.exif.exifIfd['DateTimeDigitized'] = '2020:01:01 12:00:00';

      final oldJpgBytes = Uint8List.fromList(img.encodeJpg(sampleImage));

      // 2. Adjust timestamp using Helperfunctions
      final targetTime = DateTime(2026, 10, 13, 10, 30, 45);
      final adjustedBytes = await Helperfunctions.prepareImageBytesWithCurrentTimestamp(
        oldJpgBytes,
        targetDateTime: targetTime,
      );

      // 3. Verify the updated EXIF metadata
      final updatedExif = img.decodeJpgExif(adjustedBytes);
      expect(updatedExif, isNotNull);
      expect(updatedExif!.imageIfd['DateTime']?.toString(), equals('2026:10:13 10:30:45'));
      expect(updatedExif.exifIfd['DateTimeOriginal']?.toString(), equals('2026:10:13 10:30:45'));
      expect(updatedExif.exifIfd['DateTimeDigitized']?.toString(), equals('2026:10:13 10:30:45'));
    });

    test('prepareImageBytesWithCurrentTimestamp defaults to DateTime.now()', () async {
      final sampleImage = img.Image(width: 10, height: 10);
      final plainJpgBytes = Uint8List.fromList(img.encodeJpg(sampleImage));

      final before = DateTime.now();
      final adjustedBytes = await Helperfunctions.prepareImageBytesWithCurrentTimestamp(plainJpgBytes);

      final updatedExif = img.decodeJpgExif(adjustedBytes);
      expect(updatedExif, isNotNull);

      final dateStr = updatedExif!.exifIfd['DateTimeOriginal']?.toString();
      expect(dateStr, isNotNull);

      // Date string format is YYYY:MM:DD HH:MM:SS
      final parts = dateStr!.split(' ');
      final dateParts = parts[0].split(':').map(int.parse).toList();
      expect(dateParts[0], equals(before.year));
      expect(dateParts[1], equals(before.month));
      expect(dateParts[2], equals(before.day));
    });
  });
}
