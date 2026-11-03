import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:selecta_ops/models/placement_report_models.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/placement_report_builder.dart';

/// Calculation result for table column widths fitting on A4 landscape.
class ColumnWidthsResult {
  final double storeWidth;
  final double productColWidth;
  final double scoreWidth;
  final double newProductWidth;
  final bool fitsOnPage;

  const ColumnWidthsResult({
    required this.storeWidth,
    required this.productColWidth,
    required this.scoreWidth,
    required this.newProductWidth,
    required this.fitsOnPage,
  });

  double get totalTableWidth =>
      storeWidth + (productColWidth > 0 ? productColWidth : 0) + scoreWidth + newProductWidth;
}

/// Service for generating, printing, sharing, and saving the Monthly Placement Report PDF.
class PlacementReportPdfService {
  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');

  /// Helper to sanitize any Unicode characters for standard PDF Helvetica fonts.
  static String _clean(String input) {
    return input
        .replaceAll('₱', 'PHP ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '|')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'");
  }

  /// Computes deterministic column widths based on the number of product columns.
  ///
  /// Page: A4 Landscape (842 pt width - 48 pt margins = 794 pt usable).
  /// - Score column: 36 pt
  /// - New Product column: 64 pt
  /// - Store column: 150 pt (shrinks to 120 pt if product columns would be <= 34 pt)
  /// - Minimum product column width: 34 pt
  static ColumnWidthsResult calculateColumnWidths(int productColumnCount) {
    const usableWidth = 794.0;
    const scoreWidth = 36.0;
    const newProductWidth = 64.0;
    double storeWidth = 150.0;

    if (productColumnCount <= 0) {
      return ColumnWidthsResult(
        storeWidth: storeWidth,
        productColWidth: 0,
        scoreWidth: scoreWidth,
        newProductWidth: newProductWidth,
        fitsOnPage: true,
      );
    }

    double productColWidth =
        (usableWidth - storeWidth - scoreWidth - newProductWidth) / productColumnCount;

    if (productColWidth <= 34.0) {
      storeWidth = 120.0;
      productColWidth =
          (usableWidth - storeWidth - scoreWidth - newProductWidth) / productColumnCount;
    }

    final fitsOnPage = productColWidth >= 34.0;

    return ColumnWidthsResult(
      storeWidth: storeWidth,
      productColWidth: productColWidth,
      scoreWidth: scoreWidth,
      newProductWidth: newProductWidth,
      fitsOnPage: fitsOnPage,
    );
  }

  /// Preloads and downsizes product images to ~160px width JPEG (quality 75).
  static Future<Map<String, Uint8List>> preloadAndProcessImages(
    List<String> imageUrls, {
    void Function(int current, int total)? onProgress,
  }) async {
    final distinctUrls = imageUrls.where((u) => u.trim().isNotEmpty).toSet().toList();
    final result = <String, Uint8List>{};
    if (distinctUrls.isEmpty) return result;

    int completed = 0;
    const batchSize = 6;

    for (int i = 0; i < distinctUrls.length; i += batchSize) {
      final batch = distinctUrls.sublist(i, (i + batchSize).clamp(0, distinctUrls.length));
      await Future.wait(batch.map((url) async {
        try {
          final uri = Uri.parse(url);
          final response = await http.get(uri).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final decoded = img.decodeImage(response.bodyBytes);
            if (decoded != null) {
              final resized = decoded.width > 160 ? img.copyResize(decoded, width: 160) : decoded;
              final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 75));
              result[url] = jpgBytes;
            }
          }
        } catch (_) {
          // Fallback: Image omitted from map, placeholder will be rendered
        } finally {
          completed++;
          onProgress?.call(completed, distinctUrls.length);
        }
      }));
    }

    return result;
  }

  /// Generates the raw PDF bytes for [PlacementReportData].
  static Future<Uint8List> generatePdf(
    PlacementReportData data, {
    bool includeCover = true,
    bool includePitchList = true,
    Map<String, Uint8List>? preloadedImages,
    Uint8List? preloadedLogoBytes,
  }) async {
    final pdf = pw.Document();

    // 1. Resolve branding logo
    Uint8List? logoBytes = preloadedLogoBytes;
    if (logoBytes == null) {
      try {
        final byteData = await rootBundle.load('assets/images/logo.png');
        logoBytes = byteData.buffer.asUint8List();
      } catch (_) {
        logoBytes = null;
      }
    }
    final pw.ImageProvider? logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    // 2. Resolve product images
    Map<String, Uint8List> imageMap = preloadedImages ?? {};
    if (preloadedImages == null) {
      final allUrls = <String>[];
      for (final col in data.columns) {
        for (final p in col.products) {
          if (p.imageUrl.isNotEmpty) allUrls.add(p.imageUrl);
        }
      }
      for (final np in data.newProducts) {
        if (np.imageUrl.isNotEmpty) allUrls.add(np.imageUrl);
      }
      imageMap = await preloadAndProcessImages(allUrls);
    }

    final widths = calculateColumnWidths(data.columns.length);

    // ── PAGE 1: COVER PAGE ──
    if (includeCover) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return _buildCoverPage(data, logoImage);
          },
        ),
      );
    }

    // ── PAGES 2..N: PER-DAY GRID SECTIONS ──
    for (final section in data.sections) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (pw.Context context) => _buildDayHeaderBand(section, data, logoImage),
          footer: (pw.Context context) => _buildPageFooter(
            context,
            data,
            centerText: 'PJP: ${section.day.toUpperCase()}',
          ),
          build: (pw.Context context) {
            return [
              _buildDayTable(section, data.columns, widths, imageMap, data.newProducts),
            ];
          },
        ),
      );
    }

    // ── LAST PAGES: PITCH LIST ──
    if (includePitchList && data.pitchList.isNotEmpty) {
      // Group pitch items by day
      for (final day in data.selectedDays) {
        final dayPitchItems = data.pitchList.where((item) => item.day == day).toList();
        if (dayPitchItems.isEmpty) continue;

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(24),
            header: (pw.Context context) => _buildPitchHeaderBand(day, data, logoImage),
            footer: (pw.Context context) => _buildPageFooter(
              context,
              data,
              centerText: 'PITCH LIST - ${day.toUpperCase()}',
            ),
            build: (pw.Context context) {
              return [
                _buildPitchListTable(dayPitchItems, widths.storeWidth, imageMap),
              ];
            },
          ),
        );
      }
    }

    return await pdf.save();
  }

  // ==========================================
  // Vector Graphics & Components
  // ==========================================

  /// Vector checkmark drawn via [pw.CustomPaint] so no custom font glyph is needed.
  static pw.Widget _buildCheckmark({double size = 11, PdfColor color = PdfColors.green700}) {
    return pw.CustomPaint(
      size: PdfPoint(size, size),
      painter: (PdfGraphics canvas, PdfPoint point) {
        canvas.setColor(color);
        canvas.setLineWidth(1.6);
        // PDF canvas origin (0,0) is bottom-left
        canvas.moveTo(point.x * 0.15, point.y * 0.50);
        canvas.lineTo(point.x * 0.42, point.y * 0.18);
        canvas.lineTo(point.x * 0.88, point.y * 0.82);
        canvas.strokePath();
      },
    );
  }

  /// Dash indicator for unplaced products / non-ordered new products.
  static pw.Widget _buildDash({double size = 11, PdfColor color = PdfColors.grey400}) {
    return pw.Container(
      width: size,
      height: size,
      alignment: pw.Alignment.center,
      child: pw.Text(
        '-',
        style: pw.TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// Image or placeholder box with product initials.
  static pw.Widget _buildProductThumbnail(
    SelectaProduct product,
    double width,
    double height,
    Map<String, Uint8List> imageMap,
  ) {
    final imageBytes = imageMap[product.imageUrl];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return pw.Image(
        pw.MemoryImage(imageBytes),
        width: width,
        height: height,
        fit: pw.BoxFit.contain,
      );
    }

    final initials = _getInitials(product.productName);
    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        initials,
        style: pw.TextStyle(
          fontSize: (height * 0.35).clamp(5.0, 9.0),
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  static String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // ==========================================
  // Header Bands & Footers
  // ==========================================

  static pw.Widget _buildDayHeaderBand(
    PlacementReportDaySection section,
    PlacementReportData data,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.red800, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Image(logoImage, width: 22, height: 22),
                pw.SizedBox(width: 6),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _clean(data.companyName.toUpperCase()),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red800,
                    ),
                  ),
                  pw.Text(
                    'MONTHLY PLACEMENT REPORT - ${_monthYearFormat.format(data.month).toUpperCase()}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: PdfColors.red200, width: 0.5),
            ),
            child: pw.Text(
              'PJP: ${section.day.toUpperCase()}  |  ${section.totalStores} stores  |  Placement ${section.dayPlacementPercentage.toStringAsFixed(0)}%',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPitchHeaderBand(
    String day,
    PlacementReportData data,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue800, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Image(logoImage, width: 22, height: 22),
                pw.SizedBox(width: 6),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _clean(data.companyName.toUpperCase()),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  pw.Text(
                    'PITCH LIST (OPPORTUNITY TARGETS) - ${_monthYearFormat.format(data.month).toUpperCase()}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: PdfColors.blue200, width: 0.5),
            ),
            child: pw.Text(
              'PJP: ${day.toUpperCase()}',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(
    pw.Context context,
    PlacementReportData data, {
    required String centerText,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${_clean(data.companyName)} | Monthly Placement Report (${_monthYearFormat.format(data.month)})',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
          ),
          pw.Text(
            centerText,
            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Day Table Generation
  // ==========================================

  static pw.Widget _buildDayTable(
    PlacementReportDaySection section,
    List<PlacementReportColumn> columns,
    ColumnWidthsResult widths,
    Map<String, Uint8List> imageMap,
    List<SelectaProduct> newProducts,
  ) {
    final columnWidthMap = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(widths.storeWidth),
    };
    for (int i = 0; i < columns.length; i++) {
      columnWidthMap[i + 1] = pw.FixedColumnWidth(widths.productColWidth);
    }
    columnWidthMap[columns.length + 1] = pw.FixedColumnWidth(widths.scoreWidth);
    columnWidthMap[columns.length + 2] = pw.FixedColumnWidth(widths.newProductWidth);

    final tableRows = <pw.TableRow>[
      // 1. Header row
      _buildTableHeaderRow(columns, widths, imageMap, newProducts),

      // 2. Data rows
      for (final row in section.rows) _buildTableDataRow(row, columns),

      // 3. Footer row
      _buildTableFooterRow(section, columns),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: columnWidthMap,
      children: tableRows,
    );
  }

  static pw.TableRow _buildTableHeaderRow(
    List<PlacementReportColumn> columns,
    ColumnWidthsResult widths,
    Map<String, Uint8List> imageMap,
    List<SelectaProduct> newProducts,
  ) {
    final colWidth = widths.productColWidth;
    final fontSize = colWidth >= 44.0 ? 7.0 : (colWidth >= 38.0 ? 6.0 : 5.5);

    return pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        // Store header cell
        pw.Container(
          height: 68,
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'STORE',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'PJP Sequence Order',
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
              ),
            ],
          ),
        ),

        // Product columns headers
        for (final col in columns)
          pw.Container(
            height: 68,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            alignment: pw.Alignment.center,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (col.isPair) ...[
                  // Side by side pair images
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      _buildProductThumbnail(col.products[0], (colWidth - 6) / 2, 24, imageMap),
                      pw.SizedBox(width: 2),
                      _buildProductThumbnail(col.products[1], (colWidth - 6) / 2, 24, imageMap),
                    ],
                  ),
                ] else ...[
                  _buildProductThumbnail(col.products[0], colWidth - 4, 28, imageMap),
                ],
                pw.SizedBox(height: 2),
                pw.Text(
                  _clean(col.label),
                  maxLines: 3,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey900,
                  ),
                ),
              ],
            ),
          ),

        // Score header cell
        pw.Container(
          height: 68,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'Score',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Target',
                style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey600),
              ),
            ],
          ),
        ),

        // New Product header cell (Fixed 64 pt)
        pw.Container(
          height: 68,
          width: widths.newProductWidth,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              // Thumbnails row (fits within 64 pt)
              _buildNewProductThumbnailsHeader(newProducts, imageMap),
              pw.SizedBox(height: 3),
              pw.Text(
                'NEW PRODUCT',
                style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
              ),
              pw.Text(
                'ordered?',
                style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildNewProductThumbnailsHeader(
    List<SelectaProduct> newProducts,
    Map<String, Uint8List> imageMap,
  ) {
    if (newProducts.isEmpty) {
      return pw.Container(
        height: 16,
        alignment: pw.Alignment.center,
        child: pw.Text('-', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      );
    }

    // Show up to 3 thumbnails, or 2 thumbnails + "+N" chip
    final showCount = newProducts.length > 3 ? 2 : newProducts.length;
    final remainingCount = newProducts.length - showCount;

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        for (int i = 0; i < showCount; i++) ...[
          if (i > 0) pw.SizedBox(width: 2),
          _buildProductThumbnail(newProducts[i], 16, 16, imageMap),
        ],
        if (remainingCount > 0) ...[
          pw.SizedBox(width: 2),
          pw.Container(
            width: 16,
            height: 16,
            decoration: pw.BoxDecoration(
              color: PdfColors.blue100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              border: pw.Border.all(color: PdfColors.blue300, width: 0.5),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '+$remainingCount',
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
          ),
        ],
      ],
    );
  }

  static pw.TableRow _buildTableDataRow(
    PlacementReportRow row,
    List<PlacementReportColumn> columns,
  ) {
    final isEven = row.sequenceNumber % 2 == 0;
    final rowColor = isEven ? PdfColors.grey50 : PdfColors.white;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: rowColor),
      children: [
        // Store cell
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          alignment: pw.Alignment.centerLeft,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '${row.sequenceNumber}. ${_clean(row.store.storeName)}',
                maxLines: 2,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                ),
              ),
              if (row.store.storeAddress.trim().isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  _clean(row.store.storeAddress),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                ),
              ],
            ],
          ),
        ),

        // Product placement cells
        for (final col in columns)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            alignment: pw.Alignment.center,
            child: row.placed[col.key] == true ? _buildCheckmark(size: 11) : _buildDash(size: 11),
          ),

        // Score cell
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text(
            row.scoreText,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: row.placedCount == row.totalCount && row.totalCount > 0
                  ? PdfColors.green800
                  : PdfColors.grey900,
            ),
          ),
        ),

        // New Product cell
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: row.orderedNewProduct
              ? _buildCheckmark(size: 11, color: PdfColors.blue700)
              : _buildDash(size: 11),
        ),
      ],
    );
  }

  static pw.TableRow _buildTableFooterRow(
    PlacementReportDaySection section,
    List<PlacementReportColumn> columns,
  ) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        // Label cell
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            'Stores placed',
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
        ),

        // Per-column coverage
        for (final col in columns)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '${section.perColumnPlacedCount[col.key] ?? 0}/${section.totalStores}',
              style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
            ),
          ),

        // Day total percentage
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text(
            '${section.dayPlacementPercentage.toStringAsFixed(0)}%',
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
        ),

        // New Product total
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          alignment: pw.Alignment.center,
          child: pw.Text(
            '${section.newProductOrderedCount}/${section.totalStores}',
            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Cover Page Generation
  // ==========================================

  static pw.Widget _buildCoverPage(
    PlacementReportData data,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 36, height: 36),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _clean(data.companyName.toUpperCase()),
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'MONTHLY PLACEMENT REPORT',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    pw.Text(
                      'Coverage & Opportunities Summary | ${_monthYearFormat.format(data.month).toUpperCase()}',
                      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Text(
                    'Prepared: ${_dateFormat.format(data.generatedDate)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'CONFIDENTIAL | CLIENT-SAFE',
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
                ),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 16),

        // Key Metrics Summary Cards
        pw.Row(
          children: [
            _buildCoverStatCard(
              title: 'SELECTED PJP DAYS',
              value: '${data.selectedDays.length} Days',
              subtext: data.selectedDays.join(', '),
              color: PdfColors.indigo700,
              backgroundColor: PdfColors.indigo50,
            ),
            pw.SizedBox(width: 8),
            _buildCoverStatCard(
              title: 'TOTAL STORES',
              value: '${data.summary.totalStoresInPickedDays}',
              subtext: 'Across scheduled days',
              color: PdfColors.blue700,
              backgroundColor: PdfColors.blue50,
            ),
            pw.SizedBox(width: 8),
            _buildCoverStatCard(
              title: 'OVERALL PLACEMENT',
              value: '${data.summary.overallPlacementPercentage.toStringAsFixed(1)}%',
              subtext: '${data.summary.overallPlacedTargets} / ${data.summary.overallTotalTargets} targets placed',
              color: PdfColors.green700,
              backgroundColor: PdfColors.green50,
            ),
            pw.SizedBox(width: 8),
            _buildCoverStatCard(
              title: 'NEW PRODUCT ORDERS',
              value: '${data.summary.storesWithNewProduct} / ${data.summary.totalStoresInPickedDays}',
              subtext: data.summary.totalStoresInPickedDays > 0
                  ? '${((data.summary.storesWithNewProduct / data.summary.totalStoresInPickedDays) * 100).toStringAsFixed(0)}% penetration'
                  : '0% penetration',
              color: PdfColors.orange700,
              backgroundColor: PdfColors.orange50,
            ),
          ],
        ),

        if (data.summary.unscheduledStoresCount > 0) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: PdfColors.amber300, width: 0.5),
            ),
            child: pw.Text(
              'Notice: ${data.summary.unscheduledStoresCount} store(s) currently have no assigned PJP schedule and are excluded from day pages.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.amber900),
            ),
          ),
        ],

        pw.SizedBox(height: 14),

        // Split Section: Top/Bottom Products & Report Legend
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left: Top & Bottom Products
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PRODUCT COVERAGE HIGHLIGHTS',
                    style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                  ),
                  pw.SizedBox(height: 6),
                  _buildProductCoverageTable(
                    title: 'Top 3 Best Sellers by Coverage',
                    products: data.summary.topProducts,
                    headerColor: PdfColors.green100,
                  ),
                  pw.SizedBox(height: 10),
                  _buildProductCoverageTable(
                    title: 'Bottom 3 Best Sellers (Opportunity Focus)',
                    products: data.summary.bottomProducts,
                    headerColor: PdfColors.orange100,
                  ),
                ],
              ),
            ),

            pw.SizedBox(width: 14),

            // Right: Legend & Guidelines
            pw.Expanded(
              flex: 4,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'REPORT GUIDE & LEGEND',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    pw.SizedBox(height: 8),
                    _buildLegendItem(
                      icon: _buildCheckmark(size: 11, color: PdfColors.green700),
                      label: 'Placed Best Seller',
                      description: 'Store currently carries and has placed this target product.',
                    ),
                    pw.SizedBox(height: 6),
                    _buildLegendItem(
                      icon: _buildDash(size: 11, color: PdfColors.grey500),
                      label: 'Placement Opportunity',
                      description: 'Store does not yet carry this SKU; salesman pitch opportunity.',
                    ),
                    pw.SizedBox(height: 6),
                    _buildLegendItem(
                      icon: _buildCheckmark(size: 11, color: PdfColors.blue700),
                      label: 'New Product Ordered',
                      description: 'Store ordered at least 1 delivered New Product item this month.',
                    ),
                    pw.SizedBox(height: 6),
                    _buildLegendItem(
                      icon: pw.Text('A / B', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                      label: 'Paired Products',
                      description: 'Merged columns count as placed when EITHER SKU is placed.',
                    ),
                    pw.SizedBox(height: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        'Client-safe document: Displays brand presence and product opportunities without exposing dealer pricing or credit details.',
                        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildCoverStatCard({
    required String title,
    required String value,
    required String subtext,
    required PdfColor color,
    required PdfColor backgroundColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: backgroundColor,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: color, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: color),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              subtext,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildProductCoverageTable({
    required String title,
    required List<PlacementReportProductCoverage> products,
    required PdfColor headerColor,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              color: headerColor,
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
            ),
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
            ),
          ),
          for (final item in products)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      _clean(item.column.label),
                      maxLines: 1,
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ),
                  pw.Text(
                    '${item.placedStores} / ${item.totalStores} stores (${item.coveragePercentage.toStringAsFixed(0)}%)',
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildLegendItem({
    required pw.Widget icon,
    required String label,
    required String description,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: 18, alignment: pw.Alignment.center, child: icon),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
              ),
              pw.Text(
                description,
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Pitch List Table Generation
  // ==========================================

  static pw.Widget _buildPitchListTable(
    List<PlacementReportPitchItem> dayPitchItems,
    double storeWidth,
    Map<String, Uint8List> imageMap,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: pw.FixedColumnWidth(storeWidth),
        1: const pw.FlexColumnWidth(),
      },
      children: [
        // Header
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'STORE',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              child: pw.Text(
                'OPPORTUNITY PITCH TARGETS (MISSING BEST SELLERS)',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
              ),
            ),
          ],
        ),

        // Store Pitch rows
        for (final item in dayPitchItems)
          pw.TableRow(
            children: [
              // Store info
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _clean(item.store.storeName),
                      maxLines: 2,
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                    if (item.store.storeAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        _clean(item.store.storeAddress),
                        maxLines: 1,
                        style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                      ),
                    ],
                  ],
                ),
              ),

              // Pitch list products
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: item.missingColumns.isEmpty
                    ? pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        child: pw.Text(
                          'All Best Sellers placed (100% complete)',
                          style: pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.green700,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      )
                    : pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Focus Pitch: ${item.nextToPitch.map((c) => _clean(c.label)).join('  |  ')}',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: item.missingColumns
                                .map((c) => _buildPitchProductChip(c, imageMap))
                                .toList(),
                          ),
                        ],
                      ),
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildPitchProductChip(
    PlacementReportColumn col,
    Map<String, Uint8List> imageMap,
  ) {
    return pw.Container(
      width: 78,
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Row(
        children: [
          _buildProductThumbnail(col.primaryProduct, 18, 18, imageMap),
          pw.SizedBox(width: 3),
          pw.Expanded(
            child: pw.Text(
              _clean(col.label),
              maxLines: 2,
              style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey900),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Print / Share / Save Actions
  // ==========================================

  /// Saves the generated PDF bytes to the device documents directory and opens it.
  static Future<File> saveAndOpenPdf(
    PlacementReportData data, {
    bool includeCover = true,
    bool includePitchList = true,
    Map<String, Uint8List>? preloadedImages,
  }) async {
    final pdfBytes = await generatePdf(
      data,
      includeCover: includeCover,
      includePitchList: includePitchList,
      preloadedImages: preloadedImages,
    );

    final directory = await getApplicationDocumentsDirectory();
    final yearMonth =
        '${data.month.year}-${data.month.month.toString().padLeft(2, '0')}';
    final fileName = 'PlacementReport_$yearMonth.pdf';

    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes, flush: true);

    await OpenFilex.open(file.path);
    return file;
  }

  /// Sends the PDF to the printer / print preview sheet.
  /// Falls back to saving & opening if print platform channels fail.
  static Future<void> printOrSharePdf(
    PlacementReportData data, {
    bool includeCover = true,
    bool includePitchList = true,
    Map<String, Uint8List>? preloadedImages,
  }) async {
    try {
      final pdfBytes = await generatePdf(
        data,
        includeCover: includeCover,
        includePitchList: includePitchList,
        preloadedImages: preloadedImages,
      );

      final yearMonth =
          '${data.month.year}-${data.month.month.toString().padLeft(2, '0')}';
      final fileName = 'PlacementReport_$yearMonth.pdf';

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: fileName,
        format: PdfPageFormat.a4.landscape,
        dynamicLayout: false,
      );
    } catch (_) {
      await saveAndOpenPdf(
        data,
        includeCover: includeCover,
        includePitchList: includePitchList,
        preloadedImages: preloadedImages,
      );
    }
  }

  /// Directly opens the system share sheet with the PDF.
  static Future<void> sharePdf(
    PlacementReportData data, {
    bool includeCover = true,
    bool includePitchList = true,
    Map<String, Uint8List>? preloadedImages,
  }) async {
    try {
      final pdfBytes = await generatePdf(
        data,
        includeCover: includeCover,
        includePitchList: includePitchList,
        preloadedImages: preloadedImages,
      );

      final yearMonth =
          '${data.month.year}-${data.month.month.toString().padLeft(2, '0')}';
      final fileName = 'PlacementReport_$yearMonth.pdf';

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
      );
    } catch (_) {
      await saveAndOpenPdf(
        data,
        includeCover: includeCover,
        includePitchList: includePitchList,
        preloadedImages: preloadedImages,
      );
    }
  }
}
