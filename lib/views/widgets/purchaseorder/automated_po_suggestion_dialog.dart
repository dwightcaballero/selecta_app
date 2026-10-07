import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/supplier_mapping_service.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/product_supplier_calendar_dialog.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

class SuggestedPoItem {
  final InventoryItem item;
  int quantity;
  final int neededQuantity;
  final int? supplierCap;
  final String note;

  SuggestedPoItem({
    required this.item,
    required this.quantity,
    required this.neededQuantity,
    this.supplierCap,
    this.note = '',
  });

  double get lineTotal => quantity * item.buyingPrice;
}

class SupplierOosItem {
  final InventoryItem item;
  final int neededQuantity;
  final String note;

  SupplierOosItem({
    required this.item,
    required this.neededQuantity,
    this.note = 'Out of stock from supplier',
  });
}

/// Modal dialog for automating Purchase Order suggestions based on dealer restock needs,
/// max stock levels, and supplier stock availability documents parsed via Gemini AI.
class AutomatedPoSuggestionDialog extends StatefulWidget {
  final List<InventoryItem> allInventory;
  final NumberFormat currencyFormat;

  const AutomatedPoSuggestionDialog({
    super.key,
    required this.allInventory,
    required this.currencyFormat,
  });

  static Future<List<PoExtractedLine>?> show({
    required BuildContext context,
    required List<InventoryItem> allInventory,
    required NumberFormat currencyFormat,
  }) {
    return showModalBottomSheet<List<PoExtractedLine>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AutomatedPoSuggestionDialog(
        allInventory: allInventory,
        currencyFormat: currencyFormat,
      ),
    );
  }

  @override
  State<AutomatedPoSuggestionDialog> createState() => _AutomatedPoSuggestionDialogState();
}

class _AutomatedPoSuggestionDialogState extends State<AutomatedPoSuggestionDialog> {
  final ImagePicker _picker = ImagePicker();
  final GeminiAiService _aiService = GeminiAiService();
  final SupplierMappingService _mappingService = SupplierMappingService();
  final SupplierOosService _oosService = SupplierOosService();

  final List<File> _pickedImages = [];
  bool _isAnalyzing = false;
  bool _hasAnalyzed = false;

  final List<SuggestedPoItem> _suggestedItems = [];
  final List<SupplierOosItem> _oosItems = [];
  DateTime? _extractedReportDate;

  int get _totalSuggestedUnits => _suggestedItems.fold(0, (acc, i) => acc + i.quantity);
  double get _totalEstimatedCost => _suggestedItems.fold(0.0, (acc, i) => acc + i.lineTotal);

  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedList = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (pickedList.isNotEmpty) {
          setState(() {
            _pickedImages.addAll(pickedList.map((x) => File(x.path)));
          });
        }
      } else {
        final XFile? file = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (file != null) {
          setState(() {
            _pickedImages.add(File(file.path));
          });
        }
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Image picker error: $e');
    }
  }

  Future<void> _scanDoc() async {
    try {
      final scanned = await FlutterDocScanner().getScannedDocumentAsImages(page: 6);
      if (scanned != null && scanned.images.isNotEmpty) {
        setState(() {
          _pickedImages.addAll(
            scanned.images.map((p) => File(p.replaceFirst('file://', ''))),
          );
        });
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Scanner error: $e');
    }
  }

  Future<void> _runSuggestionAnalysis() async {
    if (_pickedImages.isEmpty) {
      ShowMessage.warning(context, 'Please upload or scan at least one supplier stock document.');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final knownMappings = await _mappingService.getAllMappings();
      final List<Uint8List> bytesList = [];
      final List<String> mimeTypes = [];
      for (final file in _pickedImages) {
        final rawBytes = await file.readAsBytes();
        final compressedBytes = await Helperfunctions.compressImageBytes(rawBytes);
        bytesList.add(compressedBytes);
        final ext = file.path.split('.').last.toLowerCase();
        mimeTypes.add(ext == 'png' ? 'image/png' : 'image/jpeg');
      }

      // Step 1: Filter exclusively to Selecta products (active & inactive)
      final selectaCatalog = widget.allInventory
          .where((i) => i.source == InventoryProductSource.selecta)
          .toList();

      final result = await _aiService.extractSupplierStockStatusFromImages(
        imagesBytesList: bytesList,
        mimeTypes: mimeTypes,
        dealerCatalog: selectaCatalog,
        knownMappings: knownMappings,
      );

      final reportDate = result.reportDate ?? DateTime.now();
      _extractedReportDate = reportDate;

      // Step 2: Record daily scan (1 single write!) for supplier accountability calendar
      final matchedIds = result.matchedItems.map((m) => m.productId).toSet().toList();
      await _oosService.recordDailyScan(
        scanDate: reportDate,
        outOfStockProductIds: result.outOfStockProductIds,
        matchedProductIds: matchedIds,
      );

      // Step 3: Match against dealer's ACTIVE Selecta products that need restocking
      final Map<String, SupplierStockItemStatus> supplierStatusByProduct = {
        for (final m in result.matchedItems) m.productId: m,
      };

      final activeNeedingRestock = selectaCatalog
          .where((i) => i.isActive && i.isNeedsRestock)
          .toList();

      final List<SuggestedPoItem> suggestions = [];
      final List<SupplierOosItem> oosList = [];

      for (final item in activeNeedingRestock) {
        final needed = item.suggestedRestockQuantity;
        if (needed <= 0) continue;

        final supplierInfo = supplierStatusByProduct[item.id];
        final isOos = result.outOfStockProductIds.contains(item.id) ||
            (supplierInfo != null && supplierInfo.isOutOfStock);

        if (isOos) {
          // Supplier cannot deliver this product! Show note and exclude from suggestions.
          oosList.add(
            SupplierOosItem(
              item: item,
              neededQuantity: needed,
              note: 'Out of stock from supplier (needed $needed pcs)',
            ),
          );
        } else {
          // Supplier has stock
          int suggestQty = needed;
          String note = '';
          final cap = supplierInfo?.supplierAvailableQuantity;
          if (cap != null && cap > 0 && cap < needed) {
            suggestQty = cap;
            note = 'Capped at supplier max ($cap pcs)';
          }

          suggestions.add(
            SuggestedPoItem(
              item: item,
              quantity: suggestQty,
              neededQuantity: needed,
              supplierCap: cap,
              note: note,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _suggestedItems
            ..clear()
            ..addAll(suggestions);
          _oosItems
            ..clear()
            ..addAll(oosList);
          _hasAnalyzed = true;
          _isAnalyzing = false;
        });

        ShowMessage.success(
          context,
          'Generated P.O. suggestion: ${suggestions.length} available, ${oosList.length} out-of-stock from supplier.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ShowMessage.error(context, 'Analysis failed: $e');
      }
    }
  }

  void _applyToPurchaseOrder() {
    final List<PoExtractedLine> lines = [];
    for (final s in _suggestedItems) {
      if (s.quantity <= 0) continue;
      lines.add(
        PoExtractedLine(
          productId: s.item.id,
          productName: s.item.productName,
          imageUrl: s.item.imageUrl,
          productSource: s.item.source.key,
          category: s.item.category,
          tag: s.item.tag,
          buyingPrice: s.item.buyingPrice,
          sellingPrice: s.item.sellingPrice,
          quantity: s.quantity,
          rawDocText: s.item.productName,
        ),
      );
    }
    Navigator.of(context).pop(lines);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Automated P.O. Suggestion',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          'Reads supplier stock sheets & matches local low stock',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Document Upload Section
                  _buildUploadSection(colorScheme),
                  const SizedBox(height: 16),

                  if (_isAnalyzing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            '✨ Sedy AI is reading supplier stocks...',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Matching dealer catalog & filtering out-of-stock items',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else if (_hasAnalyzed) ...[
                    // Report Date Header
                    if (_extractedReportDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_note_rounded, size: 18, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Supplier Sheet Date: ${DateFormat('MMM dd, yyyy').format(_extractedReportDate!)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                    // Section 1: Suggested Items to Order
                    _buildSuggestedSection(colorScheme),
                    const SizedBox(height: 20),

                    // Section 2: Out of Stock from Supplier
                    if (_oosItems.isNotEmpty) ...[
                      _buildOosSection(colorScheme),
                      const SizedBox(height: 20),
                    ],
                  ],
                ],
              ),
            ),

            // Bottom Sticky Bar (when analyzed)
            if (_hasAnalyzed && _suggestedItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_totalSuggestedUnits Units (${_suggestedItems.length} Products)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              'Est. Total: ${widget.currencyFormat.format(_totalEstimatedCost)}',
                              style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _applyToPurchaseOrder,
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Apply to P.O.', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUploadSection(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Supplier Available Stock Documents',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Upload screenshots of Selecta stock portal or depot inventory sheets.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // Picked Images Previews
            if (_pickedImages.isNotEmpty) ...[
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pickedImages.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_pickedImages[i], width: 65, height: 65, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _pickedImages.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickImages(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(_pickedImages.isEmpty ? 'Upload Screenshots' : 'Add More'),
                ),
                OutlinedButton.icon(
                  onPressed: _scanDoc,
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Scan Sheet'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: _pickedImages.isEmpty || _isAnalyzing ? null : _runSuggestionAnalysis,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(_hasAnalyzed ? 'Re-Analyze Supplier Sheet' : 'Analyze & Suggest Restock'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              'Suggested to Order (${_suggestedItems.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Text(
              'Available at Supplier',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_suggestedItems.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No available products needed restocking from this supplier sheet.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _suggestedItems.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final s = _suggestedItems[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      CachedProductImage(
                        imageUrl: s.item.imageUrl,
                        size: 46,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.item.productName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stock: ${s.item.availableQuantity} • Low: ≤${s.item.lowStockThreshold} • Max: ${s.item.maxStock > 0 ? s.item.maxStock : 'N/A'}',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            if (s.note.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                s.note,
                                style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Quantity Stepper
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 22),
                            visualDensity: VisualDensity.compact,
                            onPressed: s.quantity > 0
                                ? () => setState(() => s.quantity--)
                                : null,
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${s.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 22),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => s.quantity++),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildOosSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Text(
              'Supplier Out of Stock (${_oosItems.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'These products are on or below low stock, but the supplier cannot fulfill them. Excluded from P.O. suggestion.',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _oosItems.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (ctx, index) {
            final oos = _oosItems[index];
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  CachedProductImage(
                    imageUrl: oos.item.imageUrl,
                    size: 42,
                    borderRadius: 8,
                    isActive: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          oos.item.productName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Stock: ${oos.item.availableQuantity} • Needed: ${oos.neededQuantity} pcs',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () {
                      ProductSupplierCalendarDialog.show(
                        context: context,
                        productId: oos.item.id,
                        productName: oos.item.productName,
                        oosService: _oosService,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 16, color: Colors.red),
                    label: const Text('History', style: TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
