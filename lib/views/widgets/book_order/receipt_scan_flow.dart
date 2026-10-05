import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/supplier_mapping_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/product_disambiguation_sheet.dart';

/// A catalog product + quantity read from a booking-app receipt.
class ScannedReceiptLine {
  final InventoryItem item;
  final int quantity;
  final String rawText;

  const ScannedReceiptLine({required this.item, required this.quantity, required this.rawText});
}

/// Final outcome of resolving an AI extraction against the catalog.
class ReceiptScanOutcome {
  final List<ScannedReceiptLine> lines;

  /// Raw receipt lines the user skipped (no Selecta equivalent assigned).
  final List<String> skipped;

  const ReceiptScanOutcome({required this.lines, required this.skipped});
}

/// A scanned line whose quantity was reduced to the available stock.
class ReceiptCapNote {
  final InventoryItem item;
  final int requested;
  final int applied;

  const ReceiptCapNote({required this.item, required this.requested, required this.applied});
}

/// How scanned items should be combined with products already in the cart.
enum ReceiptMergeMode { replace, add }

/// Store-order "Scan Receipt" flow, mirroring the Purchase Order AI scanner:
/// image source picker → Gemini extraction → product disambiguation → summary.
class ReceiptScanFlow {
  ReceiptScanFlow._();

  static final ImagePicker _picker = ImagePicker();

  /// Learned aliases for the external booking app (kept separate from supplier PO aliases).
  static final SupplierMappingService mappingService = SupplierMappingService(collectionPath: SupplierMappingService.bookingReceiptCollection);

  // ============================================================
  // 1. Image Source Picker
  // ============================================================

  static Future<List<File>?> pickImages(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: colorScheme.primary, size: 22),
                    const SizedBox(width: 8),
                    const Text('Scan Order Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sedy AI will read the products and quantities from your booking app receipt and fill in the order.',
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('receipt_scan_gallery'),
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.orange, size: 28),
                  title: const Text('Upload Screenshot(s) from Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pick 1 scrolling screenshot (auto-sliced) or multiple screenshots'),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                const Divider(height: 8),
                ListTile(
                  key: const Key('receipt_scan_document'),
                  leading: const Icon(Icons.document_scanner_outlined, color: Colors.blue, size: 28),
                  title: const Text('Scan Document (Auto-Crop, up to 4 pages)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Best clarity for printed receipts'),
                  onTap: () => Navigator.pop(ctx, 'scan'),
                ),
                const Divider(height: 8),
                ListTile(
                  key: const Key('receipt_scan_camera'),
                  leading: const Icon(Icons.camera_alt_outlined, color: Colors.green, size: 28),
                  title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return null;

    try {
      switch (source) {
        case 'gallery':
          final picked = await _picker.pickMultiImage();
          return picked.map((x) => File(x.path)).toList();
        case 'scan':
          final scanned = await FlutterDocScanner().getScannedDocumentAsImages(page: 4);
          if (scanned == null || scanned.images.isEmpty) return null;
          return scanned.images.map((p) => File(p.replaceFirst('file://', ''))).toList();
        case 'camera':
          final picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
          return picked == null ? null : [File(picked.path)];
      }
    } catch (e) {
      if (context.mounted) ShowMessage.error(context, 'Unable to get image: $e');
    }
    return null;
  }

  // ============================================================
  // 2. Merge Mode Prompt (only when the cart already has items)
  // ============================================================

  static Future<ReceiptMergeMode?> askMergeMode(BuildContext context, {required int existingSkuCount}) {
    return showDialog<ReceiptMergeMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.playlist_add_check_rounded, size: 32),
        title: const Text('Products Already Selected'),
        content: Text(
          'You already have $existingSkuCount product${existingSkuCount == 1 ? '' : 's'} in this order.\n\n'
          'Replace them with the scanned receipt, or add the scanned quantities on top?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, ReceiptMergeMode.add), child: const Text('Add')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ReceiptMergeMode.replace), child: const Text('Replace')),
        ],
      ),
    );
  }

  // ============================================================
  // 3. AI Extraction
  // ============================================================

  static Future<(ExtractedPurchaseOrderData, List<SupplierProductMapping>)> extract({
    required List<File> files,
    required List<InventoryItem> allInventory,
  }) async {
    final knownMappings = await mappingService.getAllMappings();
    final List<Uint8List> bytesList = [];
    final List<String> mimeTypes = [];
    for (final file in files) {
      bytesList.add(await file.readAsBytes());
      final ext = file.path.split('.').last.toLowerCase();
      mimeTypes.add(ext == 'png' ? 'image/png' : 'image/jpeg');
    }
    final result = await GeminiAiService().extractStoreOrderFromImages(
      imagesBytesList: bytesList,
      mimeTypes: mimeTypes,
      catalog: allInventory,
      knownMappings: knownMappings,
    );
    return (result, knownMappings);
  }

  // ============================================================
  // 4. Catalog Resolution + Human Disambiguation
  // ============================================================

  static Future<ReceiptScanOutcome> resolve(
    BuildContext context, {
    required ExtractedPurchaseOrderData result,
    required List<InventoryItem> allInventory,
    required List<SupplierProductMapping> knownMappings,
  }) async {
    final Map<String, InventoryItem> byId = {for (final item in allInventory) item.id: item};
    final List<ScannedReceiptLine> lines = [];
    final List<String> skipped = [];
    final List<AmbiguousPoItem> toClarify = [...result.ambiguousItems];

    for (final matched in result.matchedItems) {
      final inv = byId[matched.productId];
      if (inv == null) {
        toClarify.add(
          AmbiguousPoItem(
            rawText: matched.rawText.isNotEmpty ? matched.rawText : matched.matchedProductName,
            quantity: matched.quantity,
            reason: 'Product not found in the active catalog. Please assign the correct product.',
          ),
        );
        continue;
      }

      // Known multi-variant alias where the AI was not fully certain → ask the user.
      SupplierProductMapping? multi;
      final norm = SupplierProductMapping.normalize(matched.rawText);
      if (norm.isNotEmpty) {
        for (final m in knownMappings) {
          if (m.isMultiMatch && m.normalizedText == norm) {
            multi = m;
            break;
          }
        }
      }
      if (multi != null && matched.confidence < 0.95) {
        final candidates = multi.candidateProductIds.where(byId.containsKey).toList();
        toClarify.add(
          AmbiguousPoItem(
            rawText: matched.rawText,
            quantity: matched.quantity,
            candidateProductIds: candidates.isNotEmpty ? candidates : [inv.id],
            reason: 'This receipt name matches multiple products. Please confirm the exact variant.',
          ),
        );
        continue;
      }

      lines.add(ScannedReceiptLine(item: inv, quantity: matched.quantity, rawText: matched.rawText));
    }

    for (final rawUnmatched in result.unmatchedItems) {
      int qty = 1;
      String text = rawUnmatched.trim();
      final m = RegExp(r'^(.*?)\s*\(Qty:\s*(\d+)\)$', caseSensitive: false).firstMatch(text);
      if (m != null) {
        text = m.group(1)?.trim() ?? text;
        qty = int.tryParse(m.group(2) ?? '1') ?? 1;
      }
      toClarify.add(
        AmbiguousPoItem(
          rawText: text,
          quantity: qty,
          reason: 'Not recognized as a catalog product. Assign one, or tap "Skip Item" if it is a fee/discount.',
        ),
      );
    }

    if (toClarify.isNotEmpty && context.mounted) {
      await ProductDisambiguationSheet.show(
        context,
        ambiguousItems: toClarify,
        allInventory: allInventory,
        sourceLabel: 'PRINTED ON RECEIPT',
        showSellingPrice: true,
        onConfirm: (item, selected, remember) async {
          lines.add(ScannedReceiptLine(item: selected, quantity: item.quantity, rawText: item.rawText));
          if (remember) {
            await mappingService.saveOrUpdateMapping(rawSupplierText: item.rawText, product: selected);
          }
        },
        onSkip: (item) => skipped.add('${item.rawText} (Qty: ${item.quantity})'),
      );
    }

    return ReceiptScanOutcome(lines: lines, skipped: skipped);
  }

  // ============================================================
  // 5. Summary
  // ============================================================

  static Future<void> showSummary(
    BuildContext context, {
    required int skuCount,
    required int unitCount,
    required List<ReceiptCapNote> capped,
    required List<String> skipped,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        const warnColor = Color(0xFFD97706);
        final allGood = capped.isEmpty && skipped.isEmpty;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: (allGood ? Colors.green : warnColor).withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(
                        allGood ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        color: allGood ? Colors.green.shade700 : warnColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Receipt Scanned', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(
                            '$skuCount product${skuCount == 1 ? '' : 's'} • $unitCount unit${unitCount == 1 ? '' : 's'} added to the order',
                            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (capped.isNotEmpty) ...[
                        _sectionLabel('LIMITED BY AVAILABLE STOCK (${capped.length})', warnColor),
                        ...capped.map(
                          (c) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CachedProductImage(imageUrl: c.item.imageUrl, size: 38),
                            title: Text(c.item.productName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              c.applied > 0 ? 'Receipt: ${c.requested} • Added: ${c.applied}' : 'Receipt: ${c.requested} • Out of stock, not added',
                              style: const TextStyle(fontSize: 12, color: warnColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (skipped.isNotEmpty) ...[
                        _sectionLabel('SKIPPED RECEIPT LINES (${skipped.length})', colorScheme.onSurfaceVariant),
                        ...skipped.map(
                          (s) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.remove_circle_outline, color: colorScheme.outline),
                            title: Text(s, style: const TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                      if (allGood)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'All receipt lines were matched and fully available.',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please review the quantities below before saving the order.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('receipt_scan_review_button'),
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.fact_check_outlined, size: 20),
                  label: const Text('Review Order', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _sectionLabel(String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: color),
    ),
  );
}
