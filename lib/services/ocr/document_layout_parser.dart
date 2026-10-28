import 'dart:math';
import 'package:intl/intl.dart';
import 'package:selecta_ops/services/ocr/ocr_result.dart';
import 'package:selecta_ops/services/ocr/text_normalizer.dart';

/// Single parsed table or receipt row extracted from OCR lines.
class ParsedRow {
  final List<OcrLine> lines;
  final String rawText;
  final String? itemCode;
  final String description;
  final int quantity;
  final double unitPrice;
  final double lineAmount;
  final String uom;
  final bool isOutOfStock;
  final int? availableQuantity;
  final bool needsReview;
  final double confidence;
  final int pageIndex;
  final double y;

  const ParsedRow({
    this.lines = const [],
    required this.rawText,
    this.itemCode,
    required this.description,
    required this.quantity,
    this.unitPrice = 0.0,
    this.lineAmount = 0.0,
    this.uom = '',
    this.isOutOfStock = false,
    this.availableQuantity,
    this.needsReview = false,
    this.confidence = 1.0,
    this.pageIndex = 0,
    this.y = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'rawText': rawText,
        if (itemCode != null) 'itemCode': itemCode,
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'lineAmount': lineAmount,
        'uom': uom,
        'isOutOfStock': isOutOfStock,
        if (availableQuantity != null) 'availableQuantity': availableQuantity,
        'needsReview': needsReview,
        'confidence': confidence,
        'pageIndex': pageIndex,
        'y': y,
      };
}

/// Structured document header and rows extracted by document layout parser.
class ParsedDocument {
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final double totalAmount;
  final List<ParsedRow> rows;
  final double confidence;

  const ParsedDocument({
    this.invoiceNumber = '',
    this.invoiceDate,
    this.totalAmount = 0.0,
    this.rows = const [],
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'invoiceNumber': invoiceNumber,
        if (invoiceDate != null) 'invoiceDate': DateFormat('yyyy-MM-dd').format(invoiceDate!),
        'totalAmount': totalAmount,
        'rows': rows.map((r) => r.toJson()).toList(),
        'confidence': confidence,
      };
}

/// Utility for clustering lines into rows, sorting tokens, repairing OCR digits,
/// and extracting structured header + item rows from OCR results.
class DocumentLayoutParser {
  /// Clusters OCR lines into rows based on vertical proximity.
  static List<List<OcrLine>> clusterIntoRows(List<OcrLine> lines) {
    if (lines.isEmpty) return [];

    // Separate lines by page index
    final pagesMap = <int, List<OcrLine>>{};
    for (final l in lines) {
      pagesMap.putIfAbsent(l.pageIndex, () => []).add(l);
    }

    final allRows = <List<OcrLine>>[];

    for (final pageLines in pagesMap.values) {
      if (pageLines.isEmpty) continue;

      // Calculate median line height
      final heights = pageLines.map((l) => l.height).where((h) => h > 4).toList()..sort();
      final medianHeight = heights.isNotEmpty ? heights[heights.length ~/ 2] : 16.0;
      final verticalThreshold = medianHeight * 0.65;

      // Sort lines by Y center
      final sortedLines = List<OcrLine>.from(pageLines)
        ..sort((a, b) => a.centerY.compareTo(b.centerY));

      final rows = <List<OcrLine>>[];
      for (final line in sortedLines) {
        bool placed = false;
        for (final row in rows) {
          final rowCenterY = row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;
          if ((line.centerY - rowCenterY).abs() <= verticalThreshold) {
            row.add(line);
            placed = true;
            break;
          }
        }
        if (!placed) {
          rows.add([line]);
        }
      }

      // Sort each row left to right
      for (final row in rows) {
        row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      }

      // Sort rows top to bottom
      rows.sort((a, b) {
        final aY = a.first.centerY;
        final bY = b.first.centerY;
        return aY.compareTo(bY);
      });

      allRows.addAll(rows);
    }

    return allRows;
  }

  /// Corrects common OCR character confusions inside numeric tokens.
  static String cleanNumericString(String raw) {
    var s = raw.trim();
    // Strip php / PHP word prefix first
    s = s.replaceAll(RegExp(r'\bphp\b', caseSensitive: false), '');
    // Strip peso signs, currency labels, commas
    s = s.replaceAll(RegExp(r'[₱Pp\$]|,'), '');
    // Substitute common OCR letter confusions in numbers
    s = s.replaceAll('O', '0').replaceAll('o', '0');
    s = s.replaceAll('I', '1').replaceAll('l', '1').replaceAll('|', '1');
    s = s.replaceAll('S', '5').replaceAll('s', '5');
    s = s.replaceAll('B', '8');
    return s.trim();
  }

  /// Parses a double price or amount from a token.
  static double? parsePrice(String token) {
    final cleaned = cleanNumericString(token);
    final match = RegExp(r'^\d+(\.\d{1,2})?$').firstMatch(cleaned);
    if (match != null) {
      return double.tryParse(match.group(0)!);
    }
    return null;
  }

  /// Parses an integer quantity from a token.
  static int? parseQuantity(String token) {
    final cleaned = cleanNumericString(token);
    // Disallow decimals for quantities unless integer ending with .0
    if (cleaned.contains('.')) {
      if (cleaned.endsWith('.0') || cleaned.endsWith('.00')) {
        return int.tryParse(cleaned.split('.').first);
      }
      return null;
    }
    return int.tryParse(cleaned);
  }

  /// Extracts invoice number from document lines.
  static String extractInvoiceNumber(List<OcrLine> lines) {
    final invoicePatterns = [
      RegExp(r'(?:INVOICE|SI|DR|PO|ORDER)\s*(?:NO|NUMBER|#)?[:.\s-]*([A-Z0-9-]{3,20})', caseSensitive: false),
      RegExp(r'\b(?:SI|DR|PO)[-–#\s]*([0-9]{3,12})\b', caseSensitive: false),
      RegExp(r'\b(?:INV|SI)[-–#\s]*([A-Z0-9-]{3,15})\b', caseSensitive: false),
    ];

    for (final line in lines) {
      for (final p in invoicePatterns) {
        final match = p.firstMatch(line.text);
        if (match != null) {
          final candidate = match.group(1)?.trim();
          if (candidate != null && candidate.length >= 3 && !candidate.contains('DATE')) {
            return candidate;
          }
        }
      }
    }
    return '';
  }

  /// Extracts invoice date from document lines with Philippine date formats.
  static DateTime? extractInvoiceDate(List<OcrLine> lines) {
    final dateRegexes = [
      // MM/dd/yyyy or MM-dd-yyyy or yyyy-MM-dd
      RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b'),
      RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b'),
      // dd-MMM-yyyy e.g. 25-Oct-2026 or 25 Oct 2026
      RegExp(r'\b(\d{1,2})[\s-]*(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s,-]*(\d{2,4})\b', caseSensitive: false),
      // MMMM dd, yyyy e.g. October 25, 2026
      RegExp(r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})\b', caseSensitive: false),
    ];

    final dateFormats = [
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'MM/dd/yyyy',
      'M/d/yyyy',
      'MM-dd-yyyy',
      'dd/MM/yyyy',
      'd/M/yyyy',
      'd-MMM-yyyy',
      'dd-MMM-yyyy',
      'd MMM yyyy',
      'dd MMM yyyy',
      'MMMM d, yyyy',
      'MMMM dd, yyyy',
      'MMM d, yyyy',
    ];

    for (final line in lines) {
      final text = line.text;
      for (final r in dateRegexes) {
        final match = r.firstMatch(text);
        if (match != null) {
          final matchedStr = match.group(0)!;
          for (final fmt in dateFormats) {
            try {
              final d = DateFormat(fmt, 'en_US').parseLoose(matchedStr);
              // Sanity check year between 2020 and 2035
              final year = d.year < 100 ? d.year + 2000 : d.year;
              if (year >= 2020 && year <= 2035) {
                return DateTime(year, d.month, d.day);
              }
            } catch (_) {}
          }
        }
      }
    }
    return null;
  }

  /// Extracts total invoice amount from lines or sums up rows.
  static double extractTotalAmount(List<OcrLine> lines, List<ParsedRow> rows) {
    final totalPatterns = [
      RegExp(r'(?:TOTAL|GRAND\s*TOTAL|AMOUNT\s*DUE|NET\s*AMOUNT|TOTAL\s*AMOUNT)[:\s₱P]*(?:PHP\s*)?([\d,]+(?:\.\d{1,2})?)', caseSensitive: false),
    ];

    double detectedTotal = 0.0;
    for (final line in lines) {
      for (final p in totalPatterns) {
        final match = p.firstMatch(line.text);
        if (match != null) {
          final amtStr = match.group(1)?.replaceAll(',', '').trim();
          final val = double.tryParse(amtStr ?? '');
          if (val != null && val > detectedTotal) {
            detectedTotal = val;
          }
        }
      }
    }

    if (detectedTotal > 0.0) return detectedTotal;

    // Fallback: sum of parsed row line amounts
    final rowSum = rows.fold(0.0, (acc, r) => acc + (r.lineAmount > 0 ? r.lineAmount : r.quantity * r.unitPrice));
    return rowSum;
  }

  /// Eliminates duplicate rows across sliced image boundaries.
  static List<ParsedRow> deduplicateSliceOverlaps(List<ParsedRow> rows) {
    if (rows.length <= 1) return rows;

    final result = <ParsedRow>[];
    for (int i = 0; i < rows.length; i++) {
      final current = rows[i];
      if (result.isEmpty) {
        result.add(current);
        continue;
      }

      final prev = result.last;
      final samePage = prev.pageIndex == current.pageIndex;
      final sameQty = prev.quantity == current.quantity;
      final normPrev = TextNormalizer.normalize(prev.description);
      final normCurr = TextNormalizer.normalize(current.description);

      final isExactDuplicate = (normPrev == normCurr && sameQty);
      final isSliceBoundaryOverlap = !samePage &&
          sameQty &&
          TextNormalizer.tokenSetSimilarity(normPrev, normCurr) >= 0.85;

      if (!isExactDuplicate && !isSliceBoundaryOverlap) {
        result.add(current);
      }
    }

    return result;
  }
}

/// Parser for Purchase Orders and Supplier Delivery Invoices.
class PurchaseOrderParser {
  static ParsedDocument parse(OcrResult ocrResult) {
    final clusteredRows = DocumentLayoutParser.clusterIntoRows(ocrResult.allLines);
    final parsedRows = <ParsedRow>[];

    for (final rowLines in clusteredRows) {
      final rowText = rowLines.map((l) => l.text).join(' ');
      final norm = TextNormalizer.normalize(rowText);

      // Skip header rows and document metadata lines
      if (_isHeaderOrMetadata(norm)) continue;

      // Extract fields from row tokens
      final parsed = _parsePoRow(rowLines, rowText);
      if (parsed != null) {
        parsedRows.add(parsed);
      }
    }

    final deduplicatedRows = DocumentLayoutParser.deduplicateSliceOverlaps(parsedRows);
    final invoiceNumber = DocumentLayoutParser.extractInvoiceNumber(ocrResult.allLines);
    final invoiceDate = DocumentLayoutParser.extractInvoiceDate(ocrResult.allLines);
    final totalAmount = DocumentLayoutParser.extractTotalAmount(ocrResult.allLines, deduplicatedRows);

    return ParsedDocument(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      totalAmount: totalAmount,
      rows: deduplicatedRows,
    );
  }

  static bool _isHeaderOrMetadata(String norm) {
    if (norm.startsWith('total') || norm.contains('grand total') || norm.contains('amount due') || norm.contains('net amount')) return true;
    if (norm.contains('invoice') && norm.contains('date')) return true;
    if (norm.contains('description') || norm.contains('particulars')) return true;
    if (norm.contains('unit price') && norm.contains('amount')) return true;
    if (norm.contains('delivered to') || norm.contains('customer name')) return true;
    if (norm.contains('prepared by') || norm.contains('received by')) return true;
    return false;
  }

  static ParsedRow? _parsePoRow(List<OcrLine> rowLines, String rowText) {
    final tokens = rowText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;

    String? itemCode;
    int? quantity;
    double? unitPrice;
    double? lineAmount;
    String uom = '';
    final descTokens = <String>[];

    // Check first token for item code (e.g. 68765432 or 10423)
    if (RegExp(r'^\d{4,10}$').hasMatch(tokens.first)) {
      itemCode = tokens.first;
      tokens.removeAt(0);
    }

    // Inspect tokens for quantities, prices, UOM, and description
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final upper = token.toUpperCase();

      if (upper == 'CS' || upper == 'BOX' || upper == 'PC' || upper == 'PCS') {
        uom = upper;
        continue;
      }

      // Decimal price check e.g. 240.00
      final priceVal = DocumentLayoutParser.parsePrice(token);
      if (priceVal != null && token.contains('.')) {
        if (unitPrice == null) {
          unitPrice = priceVal;
        } else if (lineAmount == null) {
          lineAmount = priceVal;
        } else {
          // Additional price token (e.g. ordered vs delivered price)
          lineAmount = max(lineAmount, priceVal);
        }
        continue;
      }

      // Quantity candidate (integer)
      final qtyVal = DocumentLayoutParser.parseQuantity(token);
      if (qtyVal != null && qtyVal > 0 && qtyVal < 10000) {
        // If we haven't found a quantity yet, or if multiple quantities exist (prefer delivered/invoiced)
        if (quantity == null) {
          quantity = qtyVal;
        } else {
          // If second quantity is present in row, prefer it as delivered qty
          quantity = qtyVal;
        }
        continue;
      }

      descTokens.add(token);
    }

    final description = descTokens.join(' ').trim();
    if (description.isEmpty && itemCode == null) return null;

    // Sanity check calculation: qty * unitPrice ~= lineAmount
    final q = quantity ?? 1;
    final up = unitPrice ?? 0.0;
    final la = lineAmount ?? (q * up);

    bool needsReview = false;
    double confidence = 1.0;

    if (up > 0 && la > 0) {
      final expectedAmount = q * up;
      final diff = (expectedAmount - la).abs();
      // Tolerance: within 5% or 2 pesos
      if (diff > max(2.0, la * 0.05)) {
        needsReview = true;
        confidence = 0.7;
      }
    }

    return ParsedRow(
      lines: rowLines,
      rawText: rowText,
      itemCode: itemCode,
      description: description,
      quantity: q,
      unitPrice: up,
      lineAmount: la,
      uom: uom,
      needsReview: needsReview,
      confidence: confidence,
      pageIndex: rowLines.first.pageIndex,
      y: rowLines.first.centerY,
    );
  }
}

/// Parser for Store Receipts and Booking App screenshots.
class StoreReceiptParser {
  static ParsedDocument parse(OcrResult ocrResult) {
    // Reuses core PO parser logic with store receipt heuristics
    final doc = PurchaseOrderParser.parse(ocrResult);
    return doc;
  }
}

/// Parser for Supplier Stock Availability Sheets (OOS detection).
class SupplierStockParser {
  static ParsedDocument parse(OcrResult ocrResult) {
    final clusteredRows = DocumentLayoutParser.clusterIntoRows(ocrResult.allLines);
    final parsedRows = <ParsedRow>[];

    for (final rowLines in clusteredRows) {
      final rowText = rowLines.map((l) => l.text).join(' ');
      final norm = TextNormalizer.normalize(rowText);

      if (norm.isEmpty || norm.contains('daily stock') || norm.contains('stock status')) {
        continue;
      }

      final isOos = _checkIsOutOfStock(norm);
      final tokens = rowText.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

      String? itemCode;
      int? availQty;
      final descTokens = <String>[];

      if (tokens.isNotEmpty && RegExp(r'^\d{4,10}$').hasMatch(tokens.first)) {
        itemCode = tokens.first;
        tokens.removeAt(0);
      }

      for (final t in tokens) {
        final upper = t.toUpperCase();
        if (upper == 'OOS' || upper == 'NA' || upper == 'NONE' || upper == 'AVAILABLE' || upper == 'AVAIL') continue;

        final q = DocumentLayoutParser.parseQuantity(t);
        if (q != null && availQty == null) {
          availQty = q;
        } else {
          descTokens.add(t);
        }
      }

      final description = descTokens.join(' ').trim();
      if (description.isEmpty && itemCode == null) continue;

      parsedRows.add(
        ParsedRow(
          lines: rowLines,
          rawText: rowText,
          itemCode: itemCode,
          description: description,
          quantity: availQty ?? (isOos ? 0 : 1),
          isOutOfStock: isOos || (availQty == 0),
          availableQuantity: availQty,
          pageIndex: rowLines.first.pageIndex,
          y: rowLines.first.centerY,
        ),
      );
    }

    final invoiceDate = DocumentLayoutParser.extractInvoiceDate(ocrResult.allLines);

    return ParsedDocument(
      invoiceDate: invoiceDate,
      rows: parsedRows,
    );
  }

  static bool _checkIsOutOfStock(String norm) {
    final oosKeywords = [
      'oos',
      'out of stock',
      'not available',
      'none',
      'zero',
      'n a',
      'na',
      '0 stock',
    ];
    for (final kw in oosKeywords) {
      if (norm.contains(kw)) return true;
    }
    return false;
  }
}
