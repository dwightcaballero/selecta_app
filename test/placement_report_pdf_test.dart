import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement_report_models.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/placement_report_builder.dart';
import 'package:selecta_ops/services/placement_report_pdf_service.dart';

void main() {
  group('PlacementReportPdfService Tests', () {
    test('Layout math test for N = 6, 12, 16, 20 product columns', () {
      // Usable width on A4 landscape is 794 pt (842 - 2*24)
      const usableWidth = 794.0;

      // N = 6
      final res6 = PlacementReportPdfService.calculateColumnWidths(6);
      expect(res6.storeWidth, 150.0);
      expect(res6.scoreWidth, 36.0);
      expect(res6.newProductWidth, 64.0);
      expect(res6.productColWidth, (usableWidth - 150 - 36 - 64) / 6);
      expect(res6.fitsOnPage, isTrue);
      expect(res6.storeWidth + (6 * res6.productColWidth) + res6.scoreWidth + res6.newProductWidth, closeTo(usableWidth, 0.01));

      // N = 12
      final res12 = PlacementReportPdfService.calculateColumnWidths(12);
      expect(res12.storeWidth, 150.0);
      expect(res12.productColWidth, closeTo(45.33, 0.1));
      expect(res12.fitsOnPage, isTrue);
      expect(res12.storeWidth + (12 * res12.productColWidth) + res12.scoreWidth + res12.newProductWidth, closeTo(usableWidth, 0.01));

      // N = 16 (productColWidth drops below 34 with 150 storeWidth, so storeWidth shrinks to 120)
      final res16 = PlacementReportPdfService.calculateColumnWidths(16);
      expect(res16.storeWidth, 120.0);
      expect(res16.productColWidth, closeTo(35.87, 0.1));
      expect(res16.fitsOnPage, isTrue);
      expect(res16.storeWidth + (16 * res16.productColWidth) + res16.scoreWidth + res16.newProductWidth, closeTo(usableWidth, 0.01));

      // N = 20 (even with 120 storeWidth, 574 / 20 = 28.7 < 34 pt min)
      final res20 = PlacementReportPdfService.calculateColumnWidths(20);
      expect(res20.storeWidth, 120.0);
      expect(res20.productColWidth, lessThan(34.0));
      expect(res20.fitsOnPage, isFalse);
    });

    test('A4 Landscape dimensions verification', () {
      final a4Landscape = PdfPageFormat.a4.landscape;
      expect(a4Landscape.width, closeTo(841.89, 0.5));
      expect(a4Landscape.height, closeTo(595.28, 0.5));
      expect(a4Landscape.width, greaterThan(a4Landscape.height));
    });

    test('PDF generation with fake data and stubbed images outputs valid PDF bytes', () async {
      // 1. Generate a valid tiny PNG image in pure Dart
      final dummyImage = img.Image(width: 20, height: 20);
      img.fill(dummyImage, color: img.ColorRgb8(200, 0, 0));
      final pngBytes = Uint8List.fromList(img.encodePng(dummyImage));

      // 2. Build mock products
      final p1 = SelectaProduct(
        id: 'p1',
        itemCode: 'p1',
        productName: 'Cone Classic 35',
        category: 'By Piece',
        sellingPrice: 35.0,
        imageUrl: 'https://example.com/p1.png',
        tag: ProductTag.bestSeller,
      );
      final p2 = SelectaProduct(
        id: 'p2',
        itemCode: 'p2',
        productName: 'Tub Vanilla 150',
        category: 'By Case',
        sellingPrice: 150.0,
        imageUrl: 'https://example.com/p2.png',
        tag: ProductTag.bestSeller,
      );

      final newP1 = SelectaProduct(
        id: 'np1',
        itemCode: 'np1',
        productName: 'New Supreme 40',
        category: 'By Piece',
        sellingPrice: 40.0,
        imageUrl: 'https://example.com/np1.png',
        tag: ProductTag.newProduct,
      );

      final columns = PlacementReportBuilder.buildColumns(
        bestSellers: [p1, p2],
        pairs: const [],
      );

      final store1 = Hapistore.empty()
        ..storeName = 'Store Alpha'
        ..storeAddress = '123 Main St'
        ..pjpSequence = 1;

      final store2 = Hapistore.empty()
        ..storeName = 'Store Beta'
        ..storeAddress = '456 Market St'
        ..pjpSequence = 2;

      final rows = [
        PlacementReportRow(
          store: store1,
          sequenceNumber: 1,
          placed: {columns[0].key: true, columns[1].key: false},
          placedCount: 1,
          totalCount: 2,
          orderedNewProduct: true,
        ),
        PlacementReportRow(
          store: store2,
          sequenceNumber: 2,
          placed: {columns[0].key: false, columns[1].key: false},
          placedCount: 0,
          totalCount: 2,
          orderedNewProduct: false,
        ),
      ];

      final section = PlacementReportBuilder.buildDaySection(
        day: 'Monday',
        rows: rows,
        columns: columns,
      );

      final summary = PlacementReportBuilder.buildSummary(
        sections: [section],
        columns: columns,
        totalStoresOverall: 2,
        totalScheduledStores: 2,
        unscheduledStoresCount: 0,
      );

      final pitchList = PlacementReportBuilder.buildPitchList(
        sections: [section],
        columns: columns,
      );

      final reportData = PlacementReportData(
        month: DateTime(2026, 11),
        companyName: 'TEST SELECTA DEALER',
        selectedDays: ['Monday'],
        columns: columns,
        sections: [section],
        summary: summary,
        pitchList: pitchList,
        newProducts: [newP1],
        generatedDate: DateTime(2026, 11, 3),
      );

      // Preload images map with dummy bytes for p1 and newP1, leaving p2 URL empty to test fallback placeholder
      final imageMap = {
        'https://example.com/p1.png': pngBytes,
        'https://example.com/np1.png': pngBytes,
        // p2 is omitted -> verifies initials placeholder path without crashing
      };

      final pdfBytes = await PlacementReportPdfService.generatePdf(
        reportData,
        includeCover: true,
        includePitchList: true,
        preloadedImages: imageMap,
        preloadedLogoBytes: pngBytes,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));

      // PDF magic header %PDF (0x25, 0x50, 0x44, 0x46)
      expect(pdfBytes[0], 0x25); // '%'
      expect(pdfBytes[1], 0x50); // 'P'
      expect(pdfBytes[2], 0x44); // 'D'
      expect(pdfBytes[3], 0x46); // 'F'
    });
  });
}

