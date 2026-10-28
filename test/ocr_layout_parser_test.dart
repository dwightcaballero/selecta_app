import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/ocr/document_layout_parser.dart';
import 'package:selecta_ops/services/ocr/ocr_result.dart';

void main() {
  group('DocumentLayoutParser Unit Tests', () {
    test('Row clustering groups lines by vertical center distance', () {
      final lines = [
        const OcrLine(
          text: '10423',
          boundingBox: Rect.fromLTWH(10, 100, 50, 16),
        ),
        const OcrLine(
          text: 'CORNETTO CLASSIC',
          boundingBox: Rect.fromLTWH(70, 102, 120, 16),
        ),
        const OcrLine(
          text: '12',
          boundingBox: Rect.fromLTWH(200, 101, 30, 16),
        ),
        const OcrLine(
          text: '240.00',
          boundingBox: Rect.fromLTWH(240, 100, 60, 16),
        ),
        // Line on second row
        const OcrLine(
          text: '10424',
          boundingBox: Rect.fromLTWH(10, 140, 50, 16),
        ),
        const OcrLine(
          text: 'MAGNUM ALMOND',
          boundingBox: Rect.fromLTWH(70, 141, 110, 16),
        ),
        const OcrLine(
          text: '6',
          boundingBox: Rect.fromLTWH(200, 139, 30, 16),
        ),
      ];

      final rows = DocumentLayoutParser.clusterIntoRows(lines);
      expect(rows.length, equals(2));
      expect(rows[0].length, equals(4));
      expect(rows[1].length, equals(3));
      expect(rows[0].map((l) => l.text).join(' '), equals('10423 CORNETTO CLASSIC 12 240.00'));
    });

    test('cleanNumericString repairs common OCR digit substitutions', () {
      expect(DocumentLayoutParser.cleanNumericString('O'), equals('0'));
      expect(DocumentLayoutParser.cleanNumericString('l'), equals('1'));
      expect(DocumentLayoutParser.cleanNumericString('S'), equals('5'));
      expect(DocumentLayoutParser.cleanNumericString('₱1,25O.OO'), equals('1250.00'));
      expect(DocumentLayoutParser.cleanNumericString('Php 45O'), equals('450'));
    });

    test('PurchaseOrderParser extracts invoice number, date, total, and item rows', () {
      final ocrResult = OcrResult(
        pages: [
          OcrPage(
            pageIndex: 0,
            blocks: [
              OcrBlock(
                text: 'SALES INVOICE SI-98765 Date: 10/25/2026',
                boundingBox: const Rect.fromLTWH(10, 10, 400, 30),
                lines: [
                  const OcrLine(
                    text: 'SALES INVOICE SI-98765',
                    boundingBox: Rect.fromLTWH(10, 10, 200, 20),
                  ),
                  const OcrLine(
                    text: 'Date: 10/25/2026',
                    boundingBox: Rect.fromLTWH(220, 10, 150, 20),
                  ),
                ],
              ),
              OcrBlock(
                text: 'ITEMS',
                boundingBox: const Rect.fromLTWH(10, 50, 400, 100),
                lines: [
                  const OcrLine(
                    text: '10423 CORNETTO CLASSIC 10 CS 240.00 2400.00',
                    boundingBox: Rect.fromLTWH(10, 60, 380, 20),
                  ),
                  const OcrLine(
                    text: '10424 MAGNUM ALMOND 5 CS 450.00 2250.00',
                    boundingBox: Rect.fromLTWH(10, 90, 380, 20),
                  ),
                  const OcrLine(
                    text: 'GRAND TOTAL: 4650.00',
                    boundingBox: Rect.fromLTWH(10, 130, 200, 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final doc = PurchaseOrderParser.parse(ocrResult);
      expect(doc.invoiceNumber, contains('98765'));
      expect(doc.invoiceDate, isNotNull);
      expect(doc.invoiceDate?.year, equals(2026));
      expect(doc.invoiceDate?.month, equals(10));
      expect(doc.invoiceDate?.day, equals(25));
      expect(doc.totalAmount, equals(4650.0));
      expect(doc.rows.length, equals(2));

      final firstRow = doc.rows[0];
      expect(firstRow.itemCode, equals('10423'));
      expect(firstRow.description, contains('CORNETTO CLASSIC'));
      expect(firstRow.quantity, equals(10));
      expect(firstRow.unitPrice, equals(240.0));
      expect(firstRow.lineAmount, equals(2400.0));
      expect(firstRow.needsReview, isFalse);
    });

    test('SupplierStockParser identifies OOS items and available counts', () {
      final ocrResult = OcrResult(
        pages: [
          OcrPage(
            pageIndex: 0,
            blocks: [
              OcrBlock(
                text: 'Stock Status',
                boundingBox: const Rect.fromLTWH(10, 10, 400, 100),
                lines: [
                  const OcrLine(
                    text: 'CORNETTO CHOCOLATE OOS',
                    boundingBox: Rect.fromLTWH(10, 20, 200, 20),
                  ),
                  const OcrLine(
                    text: 'MAGNUM WHITE 15',
                    boundingBox: Rect.fromLTWH(10, 50, 200, 20),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final doc = SupplierStockParser.parse(ocrResult);
      expect(doc.rows.length, equals(2));
      expect(doc.rows[0].isOutOfStock, isTrue);
      expect(doc.rows[0].quantity, equals(0));
      expect(doc.rows[1].isOutOfStock, isFalse);
      expect(doc.rows[1].availableQuantity, equals(15));
    });

    test('deduplicateSliceOverlaps eliminates boundary duplicate rows', () {
      final rows = [
        const ParsedRow(
          rawText: 'CORNETTO CLASSIC 12 CS',
          description: 'CORNETTO CLASSIC',
          quantity: 12,
          pageIndex: 0,
          y: 800,
        ),
        // Sliced overlap on page 1
        const ParsedRow(
          rawText: 'CORNETTO CLASSIC 12 CS',
          description: 'CORNETTO CLASSIC',
          quantity: 12,
          pageIndex: 1,
          y: 20,
        ),
        const ParsedRow(
          rawText: 'MAGNUM CLASSIC 6 CS',
          description: 'MAGNUM CLASSIC',
          quantity: 6,
          pageIndex: 1,
          y: 60,
        ),
      ];

      final deduped = DocumentLayoutParser.deduplicateSliceOverlaps(rows);
      expect(deduped.length, equals(2));
      expect(deduped[0].description, equals('CORNETTO CLASSIC'));
      expect(deduped[1].description, equals('MAGNUM CLASSIC'));
    });
  });
}
