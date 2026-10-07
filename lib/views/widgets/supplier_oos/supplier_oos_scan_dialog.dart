import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/supplier_mapping_service.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/supplier_oos/supplier_oos_product_picker_dialog.dart';

/// Item representation in the review and correction list.
class _ExtractedOosItem {
  SelectaProduct product;
  String rawSupplierText;
  bool isOutOfStock;
  int? supplierQuantity;
  bool isCorrected;
  bool isManuallyAdded;

  _ExtractedOosItem({
    required this.product,
    required this.rawSupplierText,
    required this.isOutOfStock,
    this.supplierQuantity,
    this.isManuallyAdded = false,
  }) : isCorrected = false;
}

/// Full interactive workflow dialog to scan supplier stock reports, verify and correct matches,
/// and record confirmed out-of-stock items for the date.
class SupplierOosScanDialog extends StatefulWidget {
  final List<SelectaProduct> products;
  final SupplierOosService oosService;
  final GeminiAiService aiService;
  final SupplierMappingService mappingService;

  const SupplierOosScanDialog({
    super.key,
    required this.products,
    required this.oosService,
    required this.aiService,
    required this.mappingService,
  });

  static Future<bool?> show({
    required BuildContext context,
    required List<SelectaProduct> products,
    SupplierOosService? oosService,
    GeminiAiService? aiService,
    SupplierMappingService? mappingService,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SupplierOosScanDialog(
        products: products,
        oosService: oosService ?? SupplierOosService(),
        aiService: aiService ?? GeminiAiService(),
        mappingService: mappingService ?? SupplierMappingService(),
      ),
    );
  }

  @override
  State<SupplierOosScanDialog> createState() => _SupplierOosScanDialogState();
}

class _SupplierOosScanDialogState extends State<SupplierOosScanDialog> {
  final ImagePicker _picker = ImagePicker();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  DateTime _inventoryDate = DateTime.now();
  final List<File> _images = [];
  bool _isAnalyzing = false;
  bool _hasAnalyzed = false;
  bool _isSaving = false;

  final List<_ExtractedOosItem> _extractedItems = [];
  String _filterStatus = 'all'; // 'all', 'oos', 'in_stock'
  String _searchFilter = '';

  @override
  void dispose() {
    super.dispose();
  }

  // ── Image Picking ──────────────────────────────────────────────────────────

  Future<void> _pickImages({bool fromCamera = false, bool useDocScanner = false}) async {
    try {
      List<File> picked = [];
      if (useDocScanner) {
        final scanned = await FlutterDocScanner().getScannedDocumentAsImages(page: 4);
        if (scanned != null && scanned.images.isNotEmpty) {
          picked = scanned.images.map((p) => File(p.replaceFirst('file://', ''))).toList();
        }
      } else if (fromCamera) {
        final photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        if (photo != null) picked = [File(photo.path)];
      } else {
        final galleryImages = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        if (galleryImages.isNotEmpty) {
          picked = galleryImages.map((x) => File(x.path)).toList();
        }
      }

      if (picked.isNotEmpty && mounted) {
        setState(() {
          _images.addAll(picked);
        });
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Error selecting image(s): $e');
    }
  }

  Future<void> _pickInventoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _inventoryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _inventoryDate = picked);
    }
  }

  // ── AI Extraction ──────────────────────────────────────────────────────────

  Future<void> _runAiExtraction() async {
    if (_images.isEmpty) {
      ShowMessage.error(context, 'Please upload at least 1 image of the supplier inventory.');
      return;
    }

    setState(() => _isAnalyzing = true);

    final statusNotifier = ValueNotifier<String>('Step 1/2: Preparing supplier report images...');
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Analyzing Supplier Stock',
      subtitle: 'Please wait while Sedy AI reads the stock document.',
      statusNotifier: statusNotifier,
    );

    try {
      final List<Uint8List> bytesList = [];
      final List<String> mimeTypes = [];

      for (int i = 0; i < _images.length; i++) {
        final file = _images[i];
        statusNotifier.value = 'Step 1/2: Compressing image ${i + 1} of ${_images.length}...';
        final rawBytes = await file.readAsBytes();
        final compressedBytes = await Helperfunctions.compressImageBytes(rawBytes);
        bytesList.add(compressedBytes);
        final ext = file.path.split('.').last.toLowerCase();
        mimeTypes.add(ext == 'png' ? 'image/png' : 'image/jpeg');
      }

      // Convert Selecta products to InventoryItem list for extraction
      final selectaCatalog = widget.products.map((p) => InventoryItem(
            id: p.id,
            productName: p.productName,
            imageUrl: p.imageUrl,
            itemCode: p.itemCode,
            buyingPrice: p.buyingPrice,
            sellingPrice: p.sellingPrice,
            isActive: p.isActive,
            stockQuantity: p.stockQuantity,
            lowStockThreshold: p.lowStockThreshold,
            source: InventoryProductSource.selecta,
            category: p.category,
            tag: p.tag,
          )).toList();

      final knownMappings = await widget.mappingService.getAllMappings();

      statusNotifier.value = 'Step 2/2: Sedy AI analyzing stock report...';
      final result = await widget.aiService.extractSupplierStockStatusFromImages(
        imagesBytesList: bytesList,
        mimeTypes: mimeTypes,
        dealerCatalog: selectaCatalog,
        knownMappings: knownMappings,
      );

      Helperfunctions.showLoading(showLoading: false);

      // Auto-update inventory date if found in document
      if (result.reportDate != null) {
        _inventoryDate = result.reportDate!;
      }

      final Map<String, SelectaProduct> productById = {
        for (final p in widget.products) p.id: p,
      };

      final List<_ExtractedOosItem> items = [];
      final Set<String> addedProductIds = {};

      for (final match in result.matchedItems) {
        final prod = productById[match.productId];
        if (prod == null) continue; // Only consider products in the app!
        if (addedProductIds.contains(prod.id)) continue;

        addedProductIds.add(prod.id);
        items.add(_ExtractedOosItem(
          product: prod,
          rawSupplierText: match.rawText,
          isOutOfStock: match.isOutOfStock,
          supplierQuantity: match.supplierAvailableQuantity,
        ));
      }

      // Also ensure any IDs in result.outOfStockProductIds are represented
      for (final oosId in result.outOfStockProductIds) {
        if (!addedProductIds.contains(oosId)) {
          final prod = productById[oosId];
          if (prod != null) {
            addedProductIds.add(prod.id);
            items.add(_ExtractedOosItem(
              product: prod,
              rawSupplierText: prod.productName,
              isOutOfStock: true,
            ));
          }
        }
      }

      // Sort by SRP ascending, then by name (same as book order page)
      _sortExtractedItems(items);

      if (mounted) {
        setState(() {
          _extractedItems
            ..clear()
            ..addAll(items);
          _hasAnalyzed = true;
          _isAnalyzing = false;
        });

        final oosCount = items.where((i) => i.isOutOfStock).length;
        ShowMessage.success(
          context,
          'Analysis complete: Found ${items.length} Selecta item(s) — $oosCount out of stock.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ShowMessage.error(context, 'AI scan failed: $e');
      }
    } finally {
      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
      }
    }
  }

  void _sortExtractedItems(List<_ExtractedOosItem> items) {
    items.sort((a, b) => Helperfunctions.compareBySrpAndName(
          nameA: a.product.productName,
          priceA: a.product.sellingPrice,
          nameB: b.product.productName,
          priceB: b.product.sellingPrice,
        ));
  }

  // ── Manual Corrections & Additions ─────────────────────────────────────────

  Future<void> _correctItemMatch(int index) async {
    final current = _extractedItems[index];
    final selected = await SupplierOosProductPickerDialog.show(
      context: context,
      products: widget.products,
      initialQuery: current.rawSupplierText.isNotEmpty ? current.rawSupplierText : current.product.productName,
      title: 'Reassign Product Match',
    );

    if (selected != null && mounted) {
      setState(() {
        current.product = selected;
        current.isCorrected = true;
        _sortExtractedItems(_extractedItems);
      });

      // Save learned alias for next time if there's raw supplier text
      if (current.rawSupplierText.isNotEmpty) {
        final invItem = InventoryItem(
          id: selected.id,
          productName: selected.productName,
          imageUrl: selected.imageUrl,
          itemCode: selected.itemCode,
          buyingPrice: selected.buyingPrice,
          sellingPrice: selected.sellingPrice,
          isActive: selected.isActive,
          stockQuantity: selected.stockQuantity,
          lowStockThreshold: selected.lowStockThreshold,
          source: InventoryProductSource.selecta,
          category: selected.category,
        );

        await widget.mappingService.saveOrUpdateMapping(
          rawSupplierText: current.rawSupplierText,
          product: invItem,
        );
      }

      if (mounted) {
        ShowMessage.info(context, 'Updated match to "${selected.productName}". AI will remember this alias.');
      }
    }
  }

  Future<void> _addMissingProduct() async {
    final selected = await SupplierOosProductPickerDialog.show(
      context: context,
      products: widget.products,
      title: 'Add Missing OOS Product',
    );

    if (selected != null && mounted) {
      // Check if already in list
      final existingIndex = _extractedItems.indexWhere((i) => i.product.id == selected.id);
      if (existingIndex >= 0) {
        setState(() {
          _extractedItems[existingIndex].isOutOfStock = true;
        });
        ShowMessage.info(context, '"${selected.productName}" is already listed and marked Out of Stock.');
        return;
      }

      setState(() {
        _extractedItems.add(_ExtractedOosItem(
          product: selected,
          rawSupplierText: selected.productName,
          isOutOfStock: true,
          isManuallyAdded: true,
        ));
        _sortExtractedItems(_extractedItems);
      });

      ShowMessage.success(context, 'Added "${selected.productName}" as Out of Stock.');
    }
  }

  void _removeItem(int index) {
    setState(() {
      _extractedItems.removeAt(index);
    });
  }

  // ── Save Records ───────────────────────────────────────────────────────────

  Future<void> _saveRecords() async {
    final oosItems = _extractedItems.where((i) => i.isOutOfStock).toList();
    final allMatchedIds = _extractedItems.map((i) => i.product.id).toSet().toList();
    final oosIds = oosItems.map((i) => i.product.id).toSet().toList();

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Saving Supplier Records',
      subtitle: 'Recording out-of-stock items for ${_dateFormat.format(_inventoryDate)}...',
    );

    try {
      await widget.oosService.recordDailyScan(
        scanDate: _inventoryDate,
        outOfStockProductIds: oosIds,
        matchedProductIds: allMatchedIds,
        notes: 'Stock scan: ${oosIds.length} OOS out of ${allMatchedIds.length} tracked Selecta products',
      );

      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.success(
          context,
          '✅ Recorded supplier stock for ${_dateFormat.format(_inventoryDate)}: ${oosIds.length} product(s) out of stock.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.error(context, 'Failed to save records: $e');
      }
    } finally {
      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
      }
    }
  }

  // ── UI Builders ────────────────────────────────────────────────────────────

  List<_ExtractedOosItem> get _filteredExtractedItems {
    return _extractedItems.where((item) {
      if (_filterStatus == 'oos' && !item.isOutOfStock) return false;
      if (_filterStatus == 'in_stock' && item.isOutOfStock) return false;
      if (_searchFilter.isNotEmpty) {
        final q = _searchFilter.toLowerCase();
        final name = item.product.productName.toLowerCase();
        final raw = item.rawSupplierText.toLowerCase();
        final code = item.product.itemCode.toLowerCase();
        return name.contains(q) || raw.contains(q) || code.contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.92;

    final isLocked = _isAnalyzing || _isSaving;

    return PopScope(
      canPop: !isLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ShowMessage.warning(context, 'Operation in progress. Please wait.');
        }
      },
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161A23) : colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.document_scanner_outlined, color: colorScheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Scan Supplier Inventory',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          Text(
                            _hasAnalyzed
                                ? 'Review and correct detected stock availability'
                                : 'Upload supplier inventory document / sheet',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: isLocked ? () => ShowMessage.warning(context, 'Operation in progress. Please wait.') : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content
              Expanded(
                child: _hasAnalyzed
                    ? _buildReviewAndCorrectionView(context)
                    : _buildUploadAndScanView(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── View 1: Upload & Initial Parameters ────────────────────────────────────

  Widget _buildUploadAndScanView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date selection card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Supplier Inventory Date',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateFormat.format(_inventoryDate),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickInventoryDate,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                  label: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Upload Options Section
          Text(
            'Upload Inventory Image(s)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload 1 or more photos or screenshots of the supplier stock report or portal snapshot.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildUploadSourceButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => _pickImages(fromCamera: false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildUploadSourceButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () => _pickImages(fromCamera: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildUploadSourceButton(
                  icon: Icons.document_scanner_outlined,
                  label: 'Doc Scanner',
                  onTap: () => _pickImages(useDocScanner: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Image Previews
          if (_images.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Selected Images (${_images.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                TextButton(
                  onPressed: () => setState(() => _images.clear()),
                  child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          _images[i],
                          width: 90,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Guidance Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The AI will identify all products on the supplier report, filter strictly to Selecta items in your app, and list out-of-stock products sorted by SRP.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Button
          FilledButton.icon(
            onPressed: _images.isNotEmpty && !_isAnalyzing ? _runAiExtraction : null,
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_isAnalyzing ? 'Analyzing with AI...' : 'Analyze Supplier Inventory'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.primary, size: 24),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── View 2: Review & Correction View ───────────────────────────────────────

  Widget _buildReviewAndCorrectionView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final oosCount = _extractedItems.where((i) => i.isOutOfStock).length;
    final inStockCount = _extractedItems.where((i) => !i.isOutOfStock).length;
    final items = _filteredExtractedItems;

    return Column(
      children: [
        // Top summary strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Row(
            children: [
              Icon(Icons.calendar_month_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Date: ${_dateFormat.format(_inventoryDate)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addMissingProduct,
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Missing Item', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Filter chips & search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              _buildFilterChip('All (${_extractedItems.length})', 'all'),
              const SizedBox(width: 8),
              _buildFilterChip('OOS ($oosCount)', 'oos', isError: true),
              const SizedBox(width: 8),
              _buildFilterChip('In Stock ($inStockCount)', 'in_stock'),
            ],
          ),
        ),

        // Search in results
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Filter results by product name...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              filled: true,
            ),
            onChanged: (val) => setState(() => _searchFilter = val.trim()),
          ),
        ),

        const Divider(height: 8),

        // Items List sorted by SRP
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 40, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text(
                        'No products match the active filter.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final item = items[index];
                    final rawIndex = _extractedItems.indexOf(item);
                    return _buildReviewItemTile(item, rawIndex);
                  },
                ),
        ),

        // Bottom CTA Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$oosCount Out of Stock',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red),
                    ),
                    Text(
                      'Only out-of-stock items are saved to calendar',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: !_isSaving ? _saveRecords : null,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded),
                label: Text('Save ($oosCount OOS)'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, {bool isError = false}) {
    final isSelected = _filterStatus == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: isError ? Colors.red.withValues(alpha: 0.2) : colorScheme.primary.withValues(alpha: 0.2),
      onSelected: (_) => setState(() => _filterStatus = value),
    );
  }

  Widget _buildReviewItemTile(_ExtractedOosItem item, int rawIndex) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isOutOfStock ? Colors.red.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: item.isOutOfStock ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(
                imageUrl: item.product.imageUrl,
                isActive: item.product.isActive,
                size: 42,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'SRP: ${_currencyFormat.format(item.product.sellingPrice)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary),
                        ),
                        if (item.isCorrected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Corrected', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Correct Match Button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Correct Product Match',
                onPressed: () => _correctItemMatch(rawIndex),
              ),
              // Remove Item Button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                tooltip: 'Remove (Not in App)',
                onPressed: () => _removeItem(rawIndex),
              ),
            ],
          ),

          if (item.rawSupplierText.isNotEmpty && item.rawSupplierText != item.product.productName) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Sheet text: "${item.rawSupplierText}"',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Status Toggle Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stock Status:',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Out of Stock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: item.isOutOfStock,
                    selectedColor: Colors.red.withValues(alpha: 0.2),
                    side: BorderSide(color: item.isOutOfStock ? Colors.red : Colors.grey.shade300),
                    onSelected: (_) => setState(() => item.isOutOfStock = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('In Stock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    selected: !item.isOutOfStock,
                    selectedColor: Colors.green.withValues(alpha: 0.2),
                    side: BorderSide(color: !item.isOutOfStock ? Colors.green : Colors.grey.shade300),
                    onSelected: (_) => setState(() => item.isOutOfStock = false),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
