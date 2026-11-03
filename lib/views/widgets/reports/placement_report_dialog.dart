import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/placement_report_models.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/placement_report_builder.dart';
import 'package:selecta_ops/services/placement_report_pdf_service.dart';
import 'package:selecta_ops/services/placement_report_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Modal dialog for configuring and generating the Monthly Placement Report PDF.
class PlacementReportDialog extends StatefulWidget {
  final PlacementReportService? reportService;
  final SelectaProductService? selectaProductService;
  final ConfigurationService? configurationService;
  final Future<List<Hapistore>> Function()? storesLoader;
  final Future<List<SelectaProduct>> Function()? bestSellersLoader;
  final Future<List<PlacementPair>> Function()? pairsLoader;
  final Future<bool> Function()? isDealerCheck;

  const PlacementReportDialog({
    super.key,
    this.reportService,
    this.selectaProductService,
    this.configurationService,
    this.storesLoader,
    this.bestSellersLoader,
    this.pairsLoader,
    this.isDealerCheck,
  });

  static Future<void> show({required BuildContext context}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PlacementReportDialog(),
    );
  }

  @override
  State<PlacementReportDialog> createState() => _PlacementReportDialogState();
}

class _PlacementReportDialogState extends State<PlacementReportDialog> {
  PlacementReportService? _lazyReportService;
  PlacementReportService get _reportService =>
      widget.reportService ?? (_lazyReportService ??= PlacementReportService());

  SelectaProductService? _lazyProductService;
  SelectaProductService get _productService =>
      widget.selectaProductService ?? (_lazyProductService ??= SelectaProductService());

  ConfigurationService? _lazyConfigService;
  ConfigurationService get _configService =>
      widget.configurationService ?? (_lazyConfigService ??= ConfigurationService());

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _selectedDays = {};
  bool _includeCover = true;
  bool _includePitchList = true;

  bool _isLoadingInitial = true;
  bool _isDealer = false;
  Map<String, int> _storeCountsByDay = {};
  int _columnCount = 0;
  ColumnWidthsResult? _widthsResult;

  // Generation state
  bool _isGenerating = false;
  String _progressText = '';
  PlacementReportData? _generatedData;
  Uint8List? _generatedPdfBytes;
  Map<String, Uint8List>? _preloadedImages;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final isDealer = widget.isDealerCheck != null
        ? await widget.isDealerCheck!()
        : await KVariables.getIsDealer();
    if (!mounted) return;

    if (!isDealer) {
      setState(() {
        _isDealer = false;
        _isLoadingInitial = false;
      });
      return;
    }

    _isDealer = true;

    try {
      // 1. Fetch stores to compute day counts
      final stores = widget.storesLoader != null
          ? await widget.storesLoader!()
          : await HapiStoreService.getListHapiStores();
      final counts = <String, int>{};
      for (final day in PjpScheduleDays.all) {
        counts[day] = stores
            .where((s) => (s.pjpSchedule?.trim().toLowerCase() ?? '') == day.toLowerCase())
            .length;
      }

      // Default: select all days with > 0 stores
      final activeDays = PjpScheduleDays.all.where((d) => (counts[d] ?? 0) > 0).toSet();

      // 2. Fetch Best Sellers & config pairs to compute column count
      final bestSellers = widget.bestSellersLoader != null
          ? await widget.bestSellersLoader!()
          : await _productService.getBestSellerProducts();
      final pairs = widget.pairsLoader != null
          ? await widget.pairsLoader!()
          : (await _configService.getConfiguration()).placementPairs;
      final cols = PlacementReportBuilder.buildColumns(
        bestSellers: bestSellers,
        pairs: pairs,
      );

      final widths = PlacementReportPdfService.calculateColumnWidths(cols.length);

      if (!mounted) return;
      setState(() {
        _storeCountsByDay = counts;
        _selectedDays.addAll(activeDays);
        _columnCount = cols.length;
        _widthsResult = widths;
        _isLoadingInitial = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingInitial = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
      _resetGenerated();
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    if (next.isAfter(DateTime(now.year, now.month, 1))) return; // Disallow future months

    setState(() {
      _selectedMonth = next;
      _resetGenerated();
    });
  }

  void _resetGenerated() {
    _generatedData = null;
    _generatedPdfBytes = null;
    _preloadedImages = null;
  }

  void _toggleDay(String day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
      _resetGenerated();
    });
  }

  void _selectAllDays() {
    setState(() {
      final daysWithStores = PjpScheduleDays.all.where((d) => (_storeCountsByDay[d] ?? 0) > 0);
      _selectedDays.addAll(daysWithStores);
      _resetGenerated();
    });
  }

  void _clearAllDays() {
    setState(() {
      _selectedDays.clear();
      _resetGenerated();
    });
  }

  Future<void> _handleGeneratePdf() async {
    if (_selectedDays.isEmpty) {
      ShowMessage.alert(
        context,
        title: 'No Days Selected',
        message: 'Please select at least one PJP day to include in the report.',
        icon: Icons.warning_amber_rounded,
      );
      return;
    }

    if (_widthsResult != null && !_widthsResult!.fitsOnPage) {
      ShowMessage.alert(
        context,
        title: 'Too Many Best Sellers',
        message: '$_columnCount Best Seller products exceed printable width on A4 Landscape. Columns would be smaller than 34 pt. Please un-tag inactive Best Sellers in Product Management before generating.',
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    // Role verification
    final isDealer = widget.isDealerCheck != null
        ? await widget.isDealerCheck!()
        : await KVariables.getIsDealer();
    if (!mounted) return;

    if (!isDealer) {
      ShowMessage.alert(
        context,
        title: 'Permission Denied',
        message: 'This report is restricted to Dealers and Admins.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    // Large dataset confirmation (Rule: confirm when stores > ~150)
    final totalSelectedStores = _selectedDays.fold<int>(
      0,
      (sum, day) => sum + (_storeCountsByDay[day] ?? 0),
    );

    if (totalSelectedStores > 150) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large Report Confirmation'),
          content: Text(
            'The selected schedule contains $totalSelectedStores stores. Generating the PDF and processing images may take several seconds. Do you wish to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() {
      _isGenerating = true;
      _progressText = 'Loading placement and delivery records...';
    });

    try {
      // 1. Load data
      final data = await _reportService.loadReportData(
        month: _selectedMonth,
        selectedDays: _selectedDays,
      );

      if (!mounted) return;
      setState(() => _progressText = 'Preloading and resizing product images...');

      // 2. Preload & resize images
      final allUrls = <String>[];
      for (final col in data.columns) {
        for (final p in col.products) {
          if (p.imageUrl.isNotEmpty) allUrls.add(p.imageUrl);
        }
      }
      for (final np in data.newProducts) {
        if (np.imageUrl.isNotEmpty) allUrls.add(np.imageUrl);
      }

      final imageMap = await PlacementReportPdfService.preloadAndProcessImages(
        allUrls,
        onProgress: (cur, tot) {
          if (mounted) {
            setState(() => _progressText = 'Processing images ($cur/$tot)...');
          }
        },
      );

      if (!mounted) return;
      setState(() => _progressText = 'Rendering printable A4 document...');

      // 3. Render PDF
      final pdfBytes = await PlacementReportPdfService.generatePdf(
        data,
        includeCover: _includeCover,
        includePitchList: _includePitchList,
        preloadedImages: imageMap,
      );

      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generatedData = data;
        _generatedPdfBytes = pdfBytes;
        _preloadedImages = imageMap;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ShowMessage.alert(
        context,
        title: 'Generation Failed',
        message: 'Could not generate report: ${e.toString().replaceAll("Exception: ", "").replaceAll("StateError: ", "")}',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _handlePrint() async {
    if (_generatedData == null) return;
    await PlacementReportPdfService.printOrSharePdf(
      _generatedData!,
      includeCover: _includeCover,
      includePitchList: _includePitchList,
      preloadedImages: _preloadedImages,
    );
  }

  Future<void> _handleShare() async {
    if (_generatedData == null) return;
    await PlacementReportPdfService.sharePdf(
      _generatedData!,
      includeCover: _includeCover,
      includePitchList: _includePitchList,
      preloadedImages: _preloadedImages,
    );
  }

  Future<void> _handleSaveAndOpen() async {
    if (_generatedData == null) return;
    await PlacementReportPdfService.saveAndOpenPdf(
      _generatedData!,
      includeCover: _includeCover,
      includePitchList: _includePitchList,
      preloadedImages: _preloadedImages,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _isLoadingInitial
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : !_isDealer
                  ? _buildAccessDenied(colorScheme)
                  : _isGenerating
                      ? _buildProgressView(colorScheme)
                      : _buildMainContent(theme, colorScheme),
        ),
      ),
    );
  }

  Widget _buildAccessDenied(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded, size: 48, color: colorScheme.error),
        const SizedBox(height: 12),
        const Text(
          'Access Restricted',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'The Monthly Placement Report is only available to Dealers and Admins.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildProgressView(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 20),
        Text(
          'Generating Placement Report',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          _progressText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMainContent(ThemeData theme, ColorScheme colorScheme) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final totalSelectedStores = _selectedDays.fold<int>(
      0,
      (sum, day) => sum + (_storeCountsByDay[day] ?? 0),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monthly Placement Report (PDF)',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Printable client-ready A4 landscape catalog sheets',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // 1. Month Picker Stepper
          Text(
            'SELECT REPORT MONTH',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _previousMonth,
                  tooltip: 'Previous Month',
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                  tooltip: isCurrentMonth ? 'Cannot select future months' : 'Next Month',
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. PJP Day Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PJP DAYS (STORES SCHEDULED)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary, letterSpacing: 0.5),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _selectAllDays,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Select All', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _clearAllDays,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PjpScheduleDays.all.map((day) {
              final count = _storeCountsByDay[day] ?? 0;
              final isSelected = _selectedDays.contains(day);
              final isEnabled = count > 0;

              return FilterChip(
                label: Text('$day ($count)'),
                selected: isSelected && isEnabled,
                onSelected: isEnabled ? (_) => _toggleDay(day) : null,
                selectedColor: colorScheme.primaryContainer,
                checkmarkColor: colorScheme.onPrimaryContainer,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: !isEnabled
                      ? colorScheme.outline
                      : isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 6),
          Text(
            'Total selected stores: $totalSelectedStores',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 18),

          // 3. Layout Check / Column Warning
          if (_widthsResult != null && !_widthsResult!.fitsOnPage) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Too many Best Sellers ($_columnCount) for A4 Landscape. Minimum column width is 34 pt. Please un-tag inactive items.',
                      style: const TextStyle(fontSize: 11.5, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 4. Report Options
          Text(
            'REPORT OPTIONS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary, letterSpacing: 0.5),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Include Cover & Executive Summary Page', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Brand logo, overall placement %, top/bottom product rankings & legend', style: TextStyle(fontSize: 11)),
            value: _includeCover,
            onChanged: (val) => setState(() {
              _includeCover = val ?? true;
              _resetGenerated();
            }),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Include Pitch List (Missing Products per Store)', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Visual sales opportunity list of unplaced Best Sellers per store', style: TextStyle(fontSize: 11)),
            value: _includePitchList,
            onChanged: (val) => setState(() {
              _includePitchList = val ?? true;
              _resetGenerated();
            }),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // 5. Actions / Generated state buttons
          if (_generatedPdfBytes != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PDF generated successfully! Ready to print, share, or view.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handleSaveAndOpen,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handleShare,
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _handlePrint,
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text('Print'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _handleGeneratePdf,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Regenerate PDF', style: TextStyle(fontSize: 12)),
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (_widthsResult != null && !_widthsResult!.fitsOnPage) || _selectedDays.isEmpty
                      ? null
                      : _handleGeneratePdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('Generate PDF'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
