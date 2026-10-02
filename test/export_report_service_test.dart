import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/export_report_service.dart';

void main() {
  group('ExportReportService CSV Formatting Tests', () {
    test('escapeCsvCell correctly escapes values with commas, quotes, and newlines', () {
      expect(ExportReportService.escapeCsvCell('Simple text'), 'Simple text');
      expect(ExportReportService.escapeCsvCell('Hello, World'), '"Hello, World"');
      expect(ExportReportService.escapeCsvCell('He said "Hello"'), '"He said ""Hello"""');
      expect(ExportReportService.escapeCsvCell('Line 1\nLine 2'), '"Line 1 Line 2"');
      expect(ExportReportService.escapeCsvCell(''), '');
      expect(ExportReportService.escapeCsvCell(null), '');
      expect(ExportReportService.escapeCsvCell(1234.56), '1234.56');
    });

    test('buildCsv prepends UTF-8 BOM and formats headers and rows', () {
      final headers = ['Date', 'Store Name', 'Amount (PHP)', 'Status'];
      final rows = [
        ['2026-10-02', 'Aling Nena Store, Manila', '1500.50', 'Delivered'],
        ['2026-10-02', '7-Eleven "Express"', '2340.00', 'Pending'],
      ];

      final csv = ExportReportService.buildCsv(headers, rows);

      // Verify UTF-8 BOM
      expect(csv.startsWith('\uFEFF'), isTrue);

      // Verify Headers
      expect(csv.contains('Date,Store Name,Amount (PHP),Status'), isTrue);

      // Verify Escaping of comma in store name
      expect(csv.contains('"Aling Nena Store, Manila"'), isTrue);

      // Verify Escaping of quotes in store name
      expect(csv.contains('"7-Eleven ""Express"""'), isTrue);

      // Verify Row count (BOM + 1 header + 2 data rows = 3 lines + trailing newline)
      final lines = csv.trim().split('\n');
      expect(lines.length, 3);
    });

    test('ExportReportType covers all required operational reports', () {
      expect(ExportReportType.values.length, 5);
      expect(ExportReportType.sales.title, contains('Sales'));
      expect(ExportReportType.deliveries.title, contains('Delivery'));
      expect(ExportReportType.creditAging.title, contains('Credit'));
      expect(ExportReportType.inventory.title, contains('Inventory'));
      expect(ExportReportType.storeVisits.title, contains('Visits'));
    });
  });
}
