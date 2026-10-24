import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/controllers/purchaseorder_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/supplier_mapping_service.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/product_disambiguation_sheet.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/po_confirmed_status_card.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/po_document_line_card.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/po_reconciliation_header.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/po_phase2_confirmation_card.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/automated_po_suggestion_dialog.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorder_catalog_page.dart';

class PurchaseorderPage extends StatefulWidget {
  const PurchaseorderPage({
    super.key,
    required this.purchaseorderID,
    required this.purchaseorder,
    this.initialOpenManualPicker = false,
    this.initialLines,
  });
  final Purchaseorder purchaseorder;
  final String purchaseorderID;
  final bool initialOpenManualPicker;
  final List<PoExtractedLine>? initialLines;

  @override
  State<PurchaseorderPage> createState() => _PurchaseorderPageState();
}

class _PurchaseorderPageState extends State<PurchaseorderPage> {
  final PurchaseOrderController _controller = PurchaseOrderController();
  final InventoryController _inventoryController = InventoryController();
  final GeminiAiService _aiService = GeminiAiService();
  final SupplierMappingService _mappingService = SupplierMappingService();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final ImagePicker _picker = ImagePicker();
  late final Stream<List<InventoryItem>> _inventoryStream;

  final TextEditingController invoiceAmountController = TextEditingController();
  final TextEditingController orderAmountController = TextEditingController();
  final TextEditingController orderNumberController = TextEditingController();
  final TextEditingController _officialInvoiceNumberController = TextEditingController();
  final TextEditingController _officialInvoiceAmountController = TextEditingController();

  bool isNewRecord = false;
  String networkImagePath = '';

  DateTime _selectedOrderDate = DateTime.now();
  DateTime _officialInvoiceDate = DateTime.now();

  List<QueryDocumentSnapshot<Purchaseorder>> _unsettledOverpayments = [];
  final Set<String> _selectedOverpaymentIds = {};

  // Document Lines in the exact order selected from the catalog
  final List<PoExtractedLine> _documentLines = [];

  bool _isSaving = false;
  bool _isComparingWithAi = false;
  bool _showDetailsCard = true;
  bool _showItemsList = true;

  final List<File> _officialInvoiceImages = [];
  InvoiceComparisonResult? _comparisonResult;

  // Phase 2: Official Invoice Extraction & Discrepancies
  final List<PoExtractedLine> _invoiceLines = [];
  List<PoInvoiceDiscrepancyItem> _comparisonDiscrepancies = [];
  double _calculatedOverpayment = 0.0;
  int _invoiceSelectedTab = 0;
  bool _showMatchedItems = false;
  bool _hasTriggeredInitialManualPicker = false;
  bool _hasPrioritizedInitialLines = false;
  bool _showPhase2Inline = false;
  bool _showPreOrderChips = false;

  bool get _isEditing => !isNewRecord;
  bool get _isPending => widget.purchaseorder.status == 'pending';
  bool get _isConfirmed => widget.purchaseorder.status == 'confirmed' || widget.purchaseorder.status == 'invoiced';

  // Real-time calculated properties from the line items
  int get _currentListUnits => _documentLines.fold(0, (acc, l) => acc + l.quantity);
  double get _currentListTotalCost => _documentLines.fold(0.0, (acc, l) => acc + l.lineTotal);
  int get _currentListCount => _documentLines.where((l) => l.quantity > 0).length;

  bool get _hasUnsavedChanges {
    if (_isEditing && _isConfirmed) return false;
    if (isNewRecord) {
      return _documentLines.isNotEmpty || orderNumberController.text.trim().isNotEmpty || _officialInvoiceNumberController.text.trim().isNotEmpty;
    }
    if (orderNumberController.text.trim() != widget.purchaseorder.poNumber &&
        orderNumberController.text.trim() != widget.purchaseorder.invoiceNumber) {
      return true;
    }
    if (_officialInvoiceNumberController.text.trim() != widget.purchaseorder.invoiceNumber) {
      return true;
    }
    if (_documentLines.length != widget.purchaseorder.items.length) return true;
    for (final line in _documentLines) {
      final origMatches = widget.purchaseorder.items.where((it) => it.productId == line.productId);
      if (origMatches.isEmpty || line.quantity != origMatches.first.effectiveQuantity) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _inventoryStream = _inventoryController.getActiveInventoryStream();
    isNewRecord = widget.purchaseorderID.isEmpty;
    if (!isNewRecord) {
      orderNumberController.text = widget.purchaseorder.poNumber.isNotEmpty ? widget.purchaseorder.poNumber : widget.purchaseorder.invoiceNumber;
      _officialInvoiceNumberController.text = widget.purchaseorder.invoiceNumber;
      orderAmountController.text = Helperfunctions.formatDoubleAmountForField(widget.purchaseorder.orderAmount);
      invoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(widget.purchaseorder.invoiceAmount);
      _selectedOrderDate = widget.purchaseorder.orderDate.toDate();
      networkImagePath = widget.purchaseorder.imagePath;
      _officialInvoiceDate = widget.purchaseorder.invoiceDate.toDate();
      _officialInvoiceAmountController.text = widget.purchaseorder.invoiceAmount > 0
          ? Helperfunctions.formatDoubleAmountForField(widget.purchaseorder.invoiceAmount)
          : '';

      // Populate document lines from existing pending/confirmed items
      for (final item in widget.purchaseorder.items) {
        _documentLines.add(
          PoExtractedLine(
            productId: item.productId,
            productName: item.productName,
            imageUrl: item.imageUrl,
            productSource: item.productSource,
            category: item.category,
            tag: item.tag,
            buyingPrice: item.buyingPrice,
            sellingPrice: item.sellingPrice,
            quantity: item.effectiveQuantity,
            rawDocText: item.productName,
          ),
        );
      }
    } else {
      if (widget.initialLines != null && widget.initialLines!.isNotEmpty) {
        _documentLines.addAll(widget.initialLines!);
        orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
      }
      _loadUnsettledOverpayments();
    }
  }

  @override
  void dispose() {
    orderAmountController.dispose();
    orderNumberController.dispose();
    invoiceAmountController.dispose();
    _officialInvoiceNumberController.dispose();
    _officialInvoiceAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadUnsettledOverpayments() async {
    try {
      final records = await _controller.getUnsettledOverpayments();
      if (mounted) setState(() => _unsettledOverpayments = records);
    } catch (_) {}
  }

  double get _totalSelectedOverpayments =>
      _controller.calculateTotalSelectedOverpayments(unsettledDocs: _unsettledOverpayments, selectedIds: _selectedOverpaymentIds);

  double get _guidedNetAmount {
    final net = _currentListTotalCost - _totalSelectedOverpayments;
    return net > 0 ? net : 0;
  }

  List<OrderItem> _buildOrderItemsFromLines() {
    return _documentLines.where((l) => l.quantity > 0).map((l) {
      return OrderItem(
        productId: l.productId,
        productName: l.productName,
        imageUrl: l.imageUrl,
        productSource: l.productSource,
        category: l.category,
        tag: l.tag,
        buyingPrice: l.buyingPrice,
        sellingPrice: l.sellingPrice,
        orderedQuantity: l.quantity,
        pickedQuantity: l.quantity,
        isPicked: false,
      );
    }).toList();
  }

  // ============================================================
  // AI Document Scanner, Manual Selection & Automated P.O.
  // ============================================================

  Future<void> _openManualPoPicker(List<InventoryItem> allInventory) async {
    final selectedLines = await Navigator.push<List<PoExtractedLine>>(
      context,
      MaterialPageRoute(
        builder: (ctx) => PurchaseOrderCatalogPage(allInventory: allInventory, existingLines: _documentLines, isDirectCreationFlow: false),
      ),
    );

    if (selectedLines != null && mounted) {
      setState(() {
        _documentLines
          ..clear()
          ..addAll(selectedLines);
        _prioritizePreOrderDeficitLines(allInventory);
        orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
      });
      if (_documentLines.isNotEmpty && mounted) {
        ShowMessage.success(context, 'Selected ${_documentLines.length} products ($_currentListUnits units) for Purchase Order.');
      }
    }
  }

  /// Prioritizes products where customer pre-order quantity exceeds available inventory
  /// by moving them to the very top of the items list.
  void _prioritizePreOrderDeficitLines(List<InventoryItem> allInventory) {
    if (_documentLines.isEmpty) return;
    final Map<String, InventoryItem> invById = {for (final i in allInventory) i.id: i};
    final Map<String, InventoryItem> invByName = {for (final i in allInventory) i.productName.trim().toLowerCase(): i};

    _documentLines.sort((a, b) {
      final invA = invById[a.productId] ?? invByName[a.productName.trim().toLowerCase()];
      final invB = invById[b.productId] ?? invByName[b.productName.trim().toLowerCase()];

      final isRecA = invA != null && invA.isPreOrderRecommended;
      final isRecB = invB != null && invB.isPreOrderRecommended;

      if (isRecA && !isRecB) return -1;
      if (!isRecA && isRecB) return 1;

      if (isRecA && isRecB) {
        final shortA = invA.hasPreOrderShortage ? invA.preOrderShortage : 0;
        final shortB = invB.hasPreOrderShortage ? invB.preOrderShortage : 0;
        if (shortA > 0 && shortB == 0) return -1;
        if (shortA == 0 && shortB > 0) return 1;
        if (shortA > 0 && shortB > 0 && shortA != shortB) {
          return shortB.compareTo(shortA); // highest shortage first
        }
        final remA = invA.remainingStockAfterPreOrder;
        final remB = invB.remainingStockAfterPreOrder;
        if (remA != remB) return remA.compareTo(remB); // lowest remaining stock first
      }
      return 0;
    });
  }

  Future<void> _openAutomatedPoSuggestions(List<InventoryItem> allInventory) async {
    final suggestedLines = await AutomatedPoSuggestionDialog.show(context: context, allInventory: allInventory, currencyFormat: _currencyFormat);

    if (suggestedLines != null && suggestedLines.isNotEmpty) {
      setState(() {
        _documentLines
          ..clear()
          ..addAll(suggestedLines);
        _prioritizePreOrderDeficitLines(allInventory);
        orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
      });
      if (mounted) {
        ShowMessage.success(context, 'Applied automated P.O. suggestion with ${_documentLines.length} products.');
      }
    }
  }

  void _addOrUpdatePreOrderLines(List<InventoryItem> deficitItems, List<InventoryItem> allInventory) {
    setState(() {
      for (final item in deficitItems) {
        final existingIndex = _documentLines.indexWhere(
          (l) => l.productId == item.id || l.productName.trim().toLowerCase() == item.productName.trim().toLowerCase(),
        );
        final neededQty = item.isPreOrderRecommended ? item.recommendedPreOrderOrderQuantity : 1;
        if (existingIndex >= 0) {
          if (_documentLines[existingIndex].quantity < neededQty) {
            _documentLines[existingIndex].quantity = neededQty;
          }
        } else {
          _documentLines.add(
            PoExtractedLine(
              productId: item.id,
              productName: item.productName,
              imageUrl: item.imageUrl,
              productSource: item.source.name,
              category: item.category,
              tag: item.tag,
              buyingPrice: item.buyingPrice,
              sellingPrice: item.sellingPrice,
              quantity: neededQty,
              rawDocText: item.productName,
            ),
          );
        }
      }
      _prioritizePreOrderDeficitLines(allInventory);
      orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
    });
    ShowMessage.success(context, 'Added pre-order shortage items to Purchase Order at top priority.');
  }

  /// Reusable catalog matching pipeline for official invoices (Phase 2).
  /// Runs collision guard, truncation check, multi-match mappings, and launches
  /// [ProductDisambiguationSheet] when human verification is required.
  Future<List<PoExtractedLine>> _resolveExtractionResultWithCatalog({
    required ExtractedPurchaseOrderData result,
    required List<InventoryItem> allInventory,
    required List<SupplierProductMapping> knownMappings,
    void Function(List<PoExtractedLine> currentLines)? onLiveUpdate,
  }) async {
    final Map<String, InventoryItem> byId = {for (final item in allInventory) item.id: item};

    // Collision Guard: Pre-scan to detect all colliding / duplicate instances among matchedItems.
    // If two or more rows have similar truncated text, share the same assigned product ID
    // with ellipses, or share a multi-match alias, BOTH (or all) rows MUST be clarified!
    final Set<int> allCollidingIndices = {};
    final Map<int, List<int>> collisionGroups = {};

    for (int i = 0; i < result.matchedItems.length; i++) {
      final itemA = result.matchedItems[i];
      final isTruncatedA = itemA.rawText.contains('...') || itemA.rawText.contains('…');
      final normA = SupplierProductMapping.normalize(itemA.rawText);

      for (int j = i + 1; j < result.matchedItems.length; j++) {
        final itemB = result.matchedItems[j];
        final isTruncatedB = itemB.rawText.contains('...') || itemB.rawText.contains('…');
        final normB = SupplierProductMapping.normalize(itemB.rawText);

        final sameProductId = itemA.productId.isNotEmpty && itemA.productId == itemB.productId;
        final sameRawText =
            normA.isNotEmpty &&
            normB.isNotEmpty &&
            (normA == normB ||
                ((isTruncatedA || isTruncatedB) && normA.length >= 5 && normB.length >= 5 && (normA.startsWith(normB) || normB.startsWith(normA))));

        if ((sameProductId && (isTruncatedA || isTruncatedB)) || sameRawText) {
          allCollidingIndices.add(i);
          allCollidingIndices.add(j);
          collisionGroups.putIfAbsent(i, () => [i]).add(j);
          collisionGroups.putIfAbsent(j, () => [j]).add(i);
        }
      }
    }

    final List<PoExtractedLine?> lineSlots = List.filled(result.matchedItems.length, null, growable: true);
    final List<AmbiguousPoItem> resolvedAmbiguous = [...result.ambiguousItems];

    for (int i = 0; i < result.matchedItems.length; i++) {
      final matched = result.matchedItems[i];
      final inv = byId[matched.productId];
      if (inv == null) {
        resolvedAmbiguous.add(
          AmbiguousPoItem(
            rawText: matched.rawText.isNotEmpty ? matched.rawText : matched.matchedProductName,
            quantity: matched.quantity,
            candidateProductIds: const [],
            reason: 'Product not found in catalog. Please assign the correct Selecta product equivalent.',
            documentIndex: i,
          ),
        );
        continue;
      }

      // Check if raw text matches a known multi-variant alias
      SupplierProductMapping? multiMatchMapping;
      if (matched.rawText.isNotEmpty) {
        final targetNorm = SupplierProductMapping.normalize(matched.rawText);
        for (final m in knownMappings) {
          if (m.isMultiMatch &&
              (m.normalizedText == targetNorm ||
                  (targetNorm.length >= 6 && (m.normalizedText.startsWith(targetNorm) || targetNorm.startsWith(m.normalizedText))))) {
            multiMatchMapping = m;
            break;
          }
        }
      }

      // Case 1: Both/all colliding instances must be clarified!
      if (allCollidingIndices.contains(i)) {
        final group = (collisionGroups[i] ?? [i])..sort();
        final orderInGroup = group.indexOf(i) + 1;
        final totalInGroup = group.length;

        final prefixWords = matched.rawText.replaceAll(RegExp(r'[\.\…\d]'), '').trim().toLowerCase().split(' ').take(2).join(' ');

        final candidateIds = (multiMatchMapping != null && multiMatchMapping.candidateProductIds.isNotEmpty)
            ? multiMatchMapping.candidateProductIds.where((id) => byId.containsKey(id)).toList()
            : allInventory
                  .where((item) => item.category == inv.category || (prefixWords.length >= 3 && item.productName.toLowerCase().contains(prefixWords)))
                  .take(4)
                  .map((item) => item.id)
                  .toList();

        resolvedAmbiguous.add(
          AmbiguousPoItem(
            rawText: matched.rawText,
            quantity: matched.quantity,
            candidateProductIds: candidateIds,
            reason: 'Similar truncated instance (Row $orderInGroup of $totalInGroup): "${matched.rawText}". Please confirm which flavor this row is.',
            documentIndex: i,
          ),
        );
      } else if (multiMatchMapping != null && matched.confidence < 0.95) {
        // Case 2: Single item matching a known multi-variant alias, where AI was not visually 100% certain
        final candidateIds = multiMatchMapping.candidateProductIds.where((id) => byId.containsKey(id)).toList();

        resolvedAmbiguous.add(
          AmbiguousPoItem(
            rawText: matched.rawText,
            quantity: matched.quantity,
            candidateProductIds: candidateIds.isNotEmpty ? candidateIds : [matched.productId],
            reason: 'Known alias with multiple Selecta flavor options. Please confirm which variant was received.',
            documentIndex: i,
          ),
        );
      } else {
        // Case 3: Safe, unambiguous item
        lineSlots[i] = PoExtractedLine(
          productId: inv.id,
          productName: inv.productName,
          imageUrl: inv.imageUrl,
          productSource: inv.source.key,
          category: inv.category,
          tag: inv.tag,
          buyingPrice: inv.buyingPrice,
          sellingPrice: inv.sellingPrice,
          quantity: matched.quantity,
          rawDocText: matched.rawText,
        );
      }
    }

    // Include any unmatched items so the dealer can clarify & assign their Selecta equivalent
    for (final rawUnmatched in result.unmatchedItems) {
      int qty = 1;
      String cleanText = rawUnmatched.trim();
      final qtyMatch = RegExp(r'^(.*?)\s*\(Qty:\s*(\d+)\)$', caseSensitive: false).firstMatch(cleanText);
      if (qtyMatch != null) {
        cleanText = qtyMatch.group(1)?.trim() ?? cleanText;
        qty = int.tryParse(qtyMatch.group(2) ?? '1') ?? 1;
      }
      resolvedAmbiguous.add(
        AmbiguousPoItem(
          rawText: cleanText,
          quantity: qty,
          candidateProductIds: const [],
          reason: 'Unmatched item from invoice receipt. Please assign the equivalent Selecta product.',
        ),
      );
    }

    if (onLiveUpdate != null) {
      onLiveUpdate(lineSlots.whereType<PoExtractedLine>().toList());
    }

    // Handle ambiguous or truncated items via Admin Disambiguation Modal
    if (resolvedAmbiguous.isNotEmpty && mounted) {
      await ProductDisambiguationSheet.show(
        context,
        ambiguousItems: resolvedAmbiguous,
        allInventory: allInventory,
        onConfirm: (item, selectedProduct, remember) async {
          final newLine = PoExtractedLine(
            productId: selectedProduct.id,
            productName: selectedProduct.productName,
            imageUrl: selectedProduct.imageUrl,
            productSource: selectedProduct.source.key,
            category: selectedProduct.category,
            tag: selectedProduct.tag,
            buyingPrice: selectedProduct.buyingPrice,
            sellingPrice: selectedProduct.sellingPrice,
            quantity: item.quantity,
            rawDocText: item.rawText,
            isCorrected: true,
          );

          if (item.documentIndex != null && item.documentIndex! < lineSlots.length) {
            lineSlots[item.documentIndex!] = newLine;
          } else {
            lineSlots.add(newLine);
          }

          if (onLiveUpdate != null) {
            onLiveUpdate(lineSlots.whereType<PoExtractedLine>().toList());
          }

          if (remember) {
            await _mappingService.saveOrUpdateMapping(rawSupplierText: item.rawText, product: selectedProduct);
          }
        },
      );
    }

    return lineSlots.whereType<PoExtractedLine>().toList();
  }

  // ============================================================
  // Dealer Correction Dialog
  // ============================================================

  Future<void> _showCorrectionDialog(int index, List<InventoryItem> allInventory, {bool isInvoice = false}) async {
    final targetList = isInvoice ? _invoiceLines : _documentLines;
    if (index >= targetList.length) return;
    final line = targetList[index];
    final searchCtrl = TextEditingController();
    InventoryItem? replacementProduct;
    int updatedQty = line.quantity;
    bool rememberCorrection = true;
    String filter = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final searchResults = filter.trim().isEmpty
                ? <InventoryItem>[]
                : allInventory
                      .where(
                        (i) => i.productName.toLowerCase().contains(filter.toLowerCase()) || i.itemCode.toLowerCase().contains(filter.toLowerCase()),
                      )
                      .take(8)
                      .toList();

            final effectiveProduct = replacementProduct;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: (isInvoice ? Colors.teal : Colors.blue).withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: Icon(
                              isInvoice ? Icons.fact_check_outlined : Icons.edit_note_rounded,
                              color: isInvoice ? Colors.teal : Colors.blue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isInvoice ? 'Assign Selecta Equivalent' : 'Correct Item #${index + 1}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Item #${index + 1} • ${isInvoice ? "Official Invoice Verification" : "Purchase Order"}',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Dedicated Actual Invoice Product Name Callout Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                              child: Icon(Icons.receipt_long_outlined, color: Colors.amber.shade900, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isInvoice ? 'ACTUAL INVOICE RECEIPT NAME:' : 'PRINTED ON DOCUMENT:',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.amber.shade900, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    line.rawDocText.isNotEmpty ? line.rawDocText : line.productName,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Current / Replaced Product Card
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                effectiveProduct != null ? 'New Selecta Equivalent to Assign:' : 'Currently Assigned Selecta Product:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colorScheme.outlineVariant),
                                ),
                                child: Row(
                                  children: [
                                    CachedProductImage(imageUrl: effectiveProduct?.imageUrl ?? line.imageUrl, size: 44),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            effectiveProduct?.productName ?? line.productName,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'Cost: ${_currencyFormat.format(effectiveProduct?.buyingPrice ?? line.buyingPrice)}',
                                            style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (effectiveProduct != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          '✓ Equivalent Selected',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Quantity editor
                              Row(
                                children: [
                                  Text(
                                    isInvoice ? 'Quantity on Invoice:' : 'Quantity on Document:',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                  ),
                                  const Spacer(),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: colorScheme.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove, size: 16),
                                          onPressed: () {
                                            if (updatedQty > 1) {
                                              setModalState(() => updatedQty--);
                                            }
                                          },
                                        ),
                                        Text('$updatedQty', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                        IconButton(icon: const Icon(Icons.add, size: 16), onPressed: () => setModalState(() => updatedQty++)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Search & Replace with correct Selecta product
                              Text(
                                isInvoice ? 'Search & Assign Equivalent Selecta Product:' : 'Replace with different Selecta product:',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: searchCtrl,
                                decoration: InputDecoration(
                                  hintText: isInvoice ? 'Search Selecta catalog by name or item code...' : 'Search catalog product name...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: filter.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: () {
                                            searchCtrl.clear();
                                            setModalState(() => filter = '');
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                onChanged: (val) => setModalState(() => filter = val),
                              ),
                              const SizedBox(height: 6),
                              if (searchResults.isNotEmpty) ...[
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 180),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: colorScheme.outlineVariant),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: searchResults.length,
                                    separatorBuilder: (_, _) => const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final item = searchResults[i];
                                      final isPicked = replacementProduct?.id == item.id;
                                      return ListTile(
                                        key: ValueKey('rep_prod_${item.id}'),
                                        dense: true,
                                        leading: CachedProductImage(imageUrl: item.imageUrl, size: 32),
                                        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        subtitle: Text(
                                          _currencyFormat.format(item.buyingPrice),
                                          style: TextStyle(fontSize: 11, color: colorScheme.primary),
                                        ),
                                        trailing: isPicked ? const Icon(Icons.check_circle, color: Colors.green, size: 20) : null,
                                        onTap: () => setModalState(() => replacementProduct = item),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Remember mapping switch
                              if (line.rawDocText.isNotEmpty)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: rememberCorrection,
                                  dense: true,
                                  onChanged: (val) => setModalState(() => rememberCorrection = val ?? true),
                                  title: const Text(
                                    'Remember this mapping for future scans',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'AI will automatically assign "${line.rawDocText}" to this product next time.',
                                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Action Buttons
                      Row(
                        children: [
                          IconButton.outlined(
                            tooltip: 'Delete Line',
                            style: IconButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(color: colorScheme.error),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                if (isInvoice) {
                                  _invoiceLines.removeAt(index);
                                  _recomputeDiscrepancies(allInventory);
                                  final invTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
                                  _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(invTotal);
                                } else {
                                  _documentLines.removeAt(index);
                                  orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
                                }
                              });
                              ShowMessage.info(context, isInvoice ? 'Line item removed from invoice.' : 'Line item removed from purchase order.');
                            },
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: Text(isInvoice ? 'Confirm Equivalent' : 'Save Changes'),
                            onPressed: () async {
                              final finalProduct = replacementProduct;
                              setState(() {
                                if (finalProduct != null) {
                                  line.productId = finalProduct.id;
                                  line.productName = finalProduct.productName;
                                  line.imageUrl = finalProduct.imageUrl;
                                  line.productSource = finalProduct.source.key;
                                  line.category = finalProduct.category;
                                  line.tag = finalProduct.tag;
                                  line.buyingPrice = finalProduct.buyingPrice;
                                  line.sellingPrice = finalProduct.sellingPrice;
                                }
                                line.quantity = updatedQty;
                                line.isCorrected = true;
                                line.isIncorrect = false;
                                if (isInvoice) {
                                  _recomputeDiscrepancies(allInventory);
                                  final invTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
                                  _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(invTotal);
                                } else {
                                  orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
                                }
                              });
                              Navigator.pop(ctx);

                              if (rememberCorrection && finalProduct != null && line.rawDocText.isNotEmpty) {
                                await _mappingService.saveOrUpdateMapping(rawSupplierText: line.rawDocText, product: finalProduct);
                              }
                              if (mounted) {
                                ShowMessage.success(context, isInvoice ? 'Invoice item #${index + 1} updated!' : 'Item #${index + 1} updated!');
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Add missed line item dialog
  Future<void> _showAddMissingLineDialog(List<InventoryItem> allInventory, {bool isInvoice = false}) async {
    final searchCtrl = TextEditingController();
    InventoryItem? selectedProduct;
    int qty = 1;
    String filter = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final searchResults = filter.trim().isEmpty
                ? allInventory.take(6).toList()
                : allInventory
                      .where(
                        (i) => i.productName.toLowerCase().contains(filter.toLowerCase()) || i.itemCode.toLowerCase().contains(filter.toLowerCase()),
                      )
                      .take(8)
                      .toList();

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isInvoice ? 'Add Line Item to Invoice' : 'Add Line Item Missed by AI',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search Selecta product...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (val) => setModalState(() => filter = val),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = searchResults[i];
                            final isPicked = selectedProduct?.id == item.id;
                            return ListTile(
                              key: ValueKey('sel_prod_${item.id}'),
                              dense: true,
                              leading: CachedProductImage(imageUrl: item.imageUrl, size: 36),
                              title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(_currencyFormat.format(item.buyingPrice), style: TextStyle(color: colorScheme.primary)),
                              trailing: isPicked ? const Icon(Icons.check_circle, color: Colors.green) : null,
                              onTap: () => setModalState(() => selectedProduct = item),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Quantity: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => setModalState(() {
                              if (qty > 1) qty--;
                            }),
                          ),
                          Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          IconButton(icon: const Icon(Icons.add), onPressed: () => setModalState(() => qty++)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: selectedProduct == null
                            ? null
                            : () {
                                final p = selectedProduct!;
                                final newLine = PoExtractedLine(
                                  productId: p.id,
                                  productName: p.productName,
                                  imageUrl: p.imageUrl,
                                  productSource: p.source.key,
                                  category: p.category,
                                  tag: p.tag,
                                  buyingPrice: p.buyingPrice,
                                  sellingPrice: p.sellingPrice,
                                  quantity: qty,
                                  rawDocText: 'Manually Added',
                                  isCorrected: true,
                                );
                                setState(() {
                                  if (isInvoice) {
                                    _invoiceLines.add(newLine);
                                    _recomputeDiscrepancies(allInventory);
                                    final invTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
                                    _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(invTotal);
                                  } else {
                                    _documentLines.add(newLine);
                                    orderAmountController.text = Helperfunctions.formatDoubleAmountForField(_currentListTotalCost);
                                  }
                                });
                                Navigator.pop(ctx);
                                if (mounted) {
                                  ShowMessage.success(context, isInvoice ? 'Item added to invoice!' : 'Item added to purchase order!');
                                }
                              },
                        child: Text(isInvoice ? 'Add to Invoice' : 'Add to Purchase Order'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // Phase 2: Official Invoice Extraction & Discrepancy Matching
  // ============================================================

  Future<void> _showOfficialInvoiceSourcePicker({bool append = false, required List<InventoryItem> allInventory}) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.teal, Colors.green]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fact_check_outlined, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scan Official Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Read invoice receipt products & reconcile with P.O.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.blue, size: 28),
                title: Text(
                  append ? 'Add More Images from Gallery' : 'Choose Images from Gallery (Multi-Select)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Pick 1 or multiple official invoice pages or photos'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleScanPhase2(fromGalleryMulti: true, append: append, allInventory: allInventory);
                },
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined, color: Colors.teal, size: 28),
                title: const Text('Scan Document (Auto-Crop, up to 4 pages)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Paper invoice verification'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleScanPhase2(useDocScanner: true, append: append, allInventory: allInventory);
                },
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Colors.green, size: 28),
                title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Snap physical document pages'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleScanPhase2(useDocScanner: false, source: ImageSource.camera, append: append, allInventory: allInventory);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleScanPhase2({
    bool fromGalleryMulti = false,
    bool useDocScanner = false,
    ImageSource source = ImageSource.camera,
    bool append = false,
    required List<InventoryItem> allInventory,
  }) async {
    List<File> newFiles = [];
    try {
      if (fromGalleryMulti) {
        final pickedList = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        if (pickedList.isNotEmpty) {
          newFiles = pickedList.map((x) => File(x.path)).toList();
        }
      } else if (useDocScanner) {
        final scanned = await FlutterDocScanner().getScannedDocumentAsImages(page: 4);
        if (scanned != null && scanned.images.isNotEmpty) {
          newFiles = scanned.images.map((p) => File(p.replaceFirst('file://', ''))).toList();
        }
      } else {
        final picked = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        if (picked != null) {
          newFiles = [File(picked.path)];
        }
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Image error: $e');
      return;
    }
    if (newFiles.isEmpty) return;
    setState(() {
      if (append) {
        _officialInvoiceImages.addAll(newFiles);
      } else {
        _officialInvoiceImages
          ..clear()
          ..addAll(newFiles);
      }
      _showPhase2Inline = true;
      _comparisonResult = null;
    });
    await _runOfficialInvoiceExtraction(allInventory);
  }

  Future<void> _runOfficialInvoiceExtraction(List<InventoryItem> allInventory) async {
    if (_officialInvoiceImages.isEmpty) {
      ShowMessage.error(context, 'Please scan at least one official invoice.');
      return;
    }
    setState(() {
      _isComparingWithAi = true;
      _comparisonResult = null;
    });

    bool isCancelled = false;
    void handleCancel() {
      if (isCancelled) return;
      isCancelled = true;
      if (mounted) {
        setState(() {
          _isComparingWithAi = false;
        });
        ShowMessage.info(context, 'Invoice reconciliation was cancelled.');
      }
    }

    final statusNotifier = ValueNotifier<String>('Step 1/3: Preparing invoice images...');
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Analyzing Official Invoice',
      subtitle: 'Comparing against original P.O. products...',
      statusNotifier: statusNotifier,
      onCancel: handleCancel,
      showCancelButton: true,
    );

    try {
      final knownMappings = await _mappingService.getAllMappings();
      if (isCancelled) return;

      final List<Uint8List> bytesList = [];
      final List<String> mimeTypes = [];
      for (int i = 0; i < _officialInvoiceImages.length; i++) {
        if (isCancelled) return;
        final file = _officialInvoiceImages[i];
        statusNotifier.value = 'Step 1/3: Preparing invoice image ${i + 1} of ${_officialInvoiceImages.length}...';
        final rawBytes = await file.readAsBytes();
        final preparedBytes = await Helperfunctions.prepareImageBytesForAi(rawBytes);
        bytesList.add(preparedBytes);
        final ext = file.path.split('.').last.toLowerCase();
        mimeTypes.add(ext == 'png' ? 'image/png' : 'image/jpeg');
      }

      if (isCancelled) return;
      statusNotifier.value = 'Step 2/3: Sedy AI reading invoice items...';
      final result = await _aiService.extractPurchaseOrderFromImages(
        imagesBytesList: bytesList,
        mimeTypes: mimeTypes,
        catalog: allInventory,
        knownMappings: knownMappings,
      );

      if (isCancelled || !mounted) return;

      statusNotifier.value = 'Step 3/3: Reconciling invoice with P.O....';
      Helperfunctions.showLoading(context: context, showLoading: false);

      final lines = await _resolveExtractionResultWithCatalog(
        result: result,
        allInventory: allInventory,
        knownMappings: knownMappings,
        onLiveUpdate: (currentLines) {
          if (isCancelled || !mounted) return;
          setState(() {
            _invoiceLines
              ..clear()
              ..addAll(currentLines);
            _recomputeDiscrepancies(allInventory);
          });
        },
      );

      if (isCancelled || !mounted) return;

      _invoiceLines
        ..clear()
        ..addAll(lines);

      if (result.invoiceNumber.isNotEmpty && _officialInvoiceNumberController.text.trim().isEmpty) {
        _officialInvoiceNumberController.text = result.invoiceNumber;
      }
      if (result.invoiceDate != null) _officialInvoiceDate = result.invoiceDate!;
      if (result.totalAmount > 0) {
        _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(result.totalAmount);
      } else {
        final calcTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
        if (calcTotal > 0) {
          _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(calcTotal);
        }
      }

      _recomputeDiscrepancies(allInventory);

      setState(() {
        _isComparingWithAi = false;
      });

      if (mounted) {
        final discrepanciesCount = _comparisonDiscrepancies.where((d) => d.type != PoDiscrepancyType.matched).length;
        if (discrepanciesCount > 0) {
          ShowMessage.warning(
            context,
            '⚠️ Invoice read: ${_invoiceLines.length} products. Detected $discrepanciesCount quantity discrepancy item(s).',
          );
        } else {
          ShowMessage.success(context, '✅ Invoice read & verified: ${_invoiceLines.length} products. All items match P.O. quantities!');
        }
      }
    } catch (e, s) {
      if (isCancelled) return;
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Official Invoice AI Extraction', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isComparingWithAi = false);
        ShowMessage.error(context, 'Invoice AI: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
      }
    }
  }

  /// Matches invoice product names and quantities against original P.O. items.
  /// Identifies shortages, missing items, excess deliveries, and calculates overpayment credit.
  void _recomputeDiscrepancies(List<InventoryItem> allInventory) {
    final Map<String, int> invoicedQtyByProductId = {};
    final Map<String, PoExtractedLine> sampleLineByProductId = {};

    for (final line in _invoiceLines) {
      invoicedQtyByProductId[line.productId] = (invoicedQtyByProductId[line.productId] ?? 0) + line.quantity;
      sampleLineByProductId.putIfAbsent(line.productId, () => line);
    }

    final List<PoInvoiceDiscrepancyItem> discrepancies = [];
    final Set<String> matchedProductIds = {};

    // 1. Compare against original PO items
    for (final poItem in widget.purchaseorder.items) {
      matchedProductIds.add(poItem.productId);
      final int orderedQty = poItem.orderedQuantity;
      final int invoicedQty = invoicedQtyByProductId[poItem.productId] ?? 0;

      PoDiscrepancyType type;
      if (invoicedQty == orderedQty) {
        type = PoDiscrepancyType.matched;
      } else if (invoicedQty == 0) {
        type = PoDiscrepancyType.missing;
      } else if (invoicedQty < orderedQty) {
        type = PoDiscrepancyType.shortage;
      } else {
        type = PoDiscrepancyType.excess;
      }

      discrepancies.add(
        PoInvoiceDiscrepancyItem(
          productId: poItem.productId,
          productName: poItem.productName,
          imageUrl: poItem.imageUrl,
          productSource: poItem.productSource,
          category: poItem.category,
          tag: poItem.tag,
          unitCost: poItem.buyingPrice,
          sellingPrice: poItem.sellingPrice,
          orderedQuantity: orderedQty,
          invoicedQuantity: invoicedQty,
          type: type,
          rawDocText: sampleLineByProductId[poItem.productId]?.rawDocText ?? '',
        ),
      );
    }

    // 2. Extra items on invoice not in the original PO
    for (final entry in invoicedQtyByProductId.entries) {
      if (!matchedProductIds.contains(entry.key)) {
        final sample = sampleLineByProductId[entry.key];
        if (sample != null) {
          discrepancies.add(
            PoInvoiceDiscrepancyItem(
              productId: sample.productId,
              productName: sample.productName,
              imageUrl: sample.imageUrl,
              productSource: sample.productSource,
              category: sample.category,
              tag: sample.tag,
              unitCost: sample.buyingPrice,
              sellingPrice: sample.sellingPrice,
              orderedQuantity: 0,
              invoicedQuantity: entry.value,
              type: PoDiscrepancyType.extra,
              rawDocText: sample.rawDocText,
            ),
          );
        }
      }
    }

    _comparisonDiscrepancies = discrepancies;

    // 3. Calculate Overpayment
    // Original PO Amount:
    final double poTotal = widget.purchaseorder.orderAmount > 0
        ? widget.purchaseorder.orderAmount
        : widget.purchaseorder.items.fold(0.0, (acc, i) => acc + (i.orderedQuantity * i.buyingPrice));

    // Delivered total from invoice items:
    final double rawDeliveredTotal = discrepancies.fold(0.0, (acc, d) => acc + (d.invoicedQuantity * d.unitCost));
    final enteredAmount = Helperfunctions.formatStringAmountToDouble(_officialInvoiceAmountController.text);
    final double effectiveDeliveredTotal = enteredAmount > 0 ? enteredAmount : rawDeliveredTotal;

    final double overpaymentDiff = poTotal - effectiveDeliveredTotal;
    _calculatedOverpayment = overpaymentDiff > 0.009 ? double.parse(overpaymentDiff.toStringAsFixed(2)) : 0.0;

    // 4. Populate _comparisonResult for complete compatibility
    final List<ConfirmedInvoiceItem> confirmedItems = [];
    final List<OrderItem> missingItems = [];

    for (final d in discrepancies) {
      if (d.invoicedQuantity > 0) {
        confirmedItems.add(
          ConfirmedInvoiceItem(
            productId: d.productId,
            productName: d.productName,
            imageUrl: d.imageUrl,
            productSource: d.productSource,
            category: d.category,
            tag: d.tag,
            unitCost: d.unitCost,
            sellingPrice: d.sellingPrice,
            orderedQuantity: d.orderedQuantity,
            deliveredQuantity: d.invoicedQuantity,
          ),
        );
      } else {
        missingItems.add(
          OrderItem(
            productId: d.productId,
            productName: d.productName,
            imageUrl: d.imageUrl,
            productSource: d.productSource,
            category: d.category,
            tag: d.tag,
            buyingPrice: d.unitCost,
            sellingPrice: d.sellingPrice,
            orderedQuantity: d.orderedQuantity,
            pickedQuantity: 0,
            isPicked: false,
          ),
        );
      }
    }

    _comparisonResult = InvoiceComparisonResult(
      confirmedItems: confirmedItems,
      missingItems: missingItems,
      invoiceNumber: _officialInvoiceNumberController.text.trim(),
      invoiceDate: _officialInvoiceDate,
      totalAmount: effectiveDeliveredTotal,
      rawAiResponse: 'Verified ${_invoiceLines.length} invoice items against ${widget.purchaseorder.items.length} P.O. items.',
    );
  }

  // ============================================================
  // Save Actions
  // ============================================================

  Future<void> onSave() async {
    final incorrectCount = _documentLines.where((l) => l.isIncorrect).length;
    if (incorrectCount > 0) {
      ShowMessage.warning(context, 'You have $incorrectCount product(s) marked as incorrect. Please correct or delete them before saving.');
      return;
    }
    if (_documentLines.isEmpty) {
      ShowMessage.error(context, 'Please scan a document or add at least one product.');
      return;
    }

    final items = _buildOrderItemsFromLines();
    final double orderAmt = _currentListTotalCost > 0
        ? _currentListTotalCost
        : Helperfunctions.formatStringAmountToDouble(orderAmountController.text);

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Saving Purchase Order',
      subtitle: 'Creating incoming floating stock & persisting order...',
    );

    try {
      await _controller.savePurchaseOrder(
        context: context,
        orderAmount: orderAmt,
        selectedOrderDate: _selectedOrderDate,
        pickedImage: null,
        selectedOverpaymentIds: _selectedOverpaymentIds,
        unsettledOverpayments: _unsettledOverpayments,
        items: items,
        poNumber: orderNumberController.text.trim(),
      );
      if (mounted) {
        Helperfunctions.showLoading(showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.success(context, '🟡 Purchase Order saved. Incoming stock is now available for ordering.');
        Navigator.pop(context);
      }
    } catch (e, s) {
      Helperfunctions.showLoading(showLoading: false);
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Save PO', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }
  }

  Future<void> onUpdatePending() async {
    final items = _buildOrderItemsFromLines();

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Updating Purchase Order',
      subtitle: 'Adjusting incoming stock allocations...',
    );

    try {
      await _controller.updatePendingPurchaseOrder(
        context: context,
        purchaseOrderId: widget.purchaseorderID,
        currentOrder: widget.purchaseorder,
        poNumber: orderNumberController.text.trim(),
        selectedOrderDate: _selectedOrderDate,
        pickedImage: null,
        networkImagePath: networkImagePath,
        items: items,
        updatedOrderAmount: _currentListTotalCost,
      );
      if (mounted) {
        Helperfunctions.showLoading(showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.success(context, 'PO items updated.');
        Navigator.pop(context);
      }
    } catch (e, s) {
      Helperfunctions.showLoading(showLoading: false);
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Update PO', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }
  }

  Future<void> _showReceiveDeliveryOptions(List<InventoryItem> allInventory) async {
    final colorScheme = Theme.of(context).colorScheme;
    final totalUnits = _documentLines.isNotEmpty
        ? _documentLines.fold<int>(0, (acc, l) => acc + l.quantity)
        : widget.purchaseorder.items.fold<int>(0, (acc, i) => acc + i.effectiveQuantity);
    final itemCount = _documentLines.isNotEmpty ? _documentLines.length : widget.purchaseorder.items.length;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.teal, Colors.green]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Receive Delivery',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$itemCount items • $totalUnits units to be received',
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Option 1: Receive Everything (Instant Restock)
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmReceiveEverything(allInventory);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.shade300, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.done_all_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Receive Everything',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Instant',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Confirm all stocks arrived in full. No missing items or overpayment — replenish inventory immediately.',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 2: Scan Document / Invoice
              InkWell(
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _showPhase2Inline = true);
                  _showOfficialInvoiceSourcePicker(allInventory: allInventory);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.teal.shade300, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.document_scanner_outlined, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scan Document / Invoice',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Capture or upload supplier invoice to cross-reference items and detect shortages or overpayment credits.',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReceiveEverything(List<InventoryItem> allInventory) async {
    final List<ConfirmedInvoiceItem> confirmed = (_documentLines.isNotEmpty
            ? _documentLines.map((l) => ConfirmedInvoiceItem(
                  productId: l.productId,
                  productName: l.productName,
                  imageUrl: l.imageUrl,
                  productSource: l.productSource,
                  category: l.category,
                  tag: l.tag,
                  unitCost: l.buyingPrice,
                  sellingPrice: l.sellingPrice,
                  orderedQuantity: l.quantity,
                  deliveredQuantity: l.quantity,
                ))
            : widget.purchaseorder.items.map((i) => ConfirmedInvoiceItem(
                  productId: i.productId,
                  productName: i.productName,
                  imageUrl: i.imageUrl,
                  productSource: i.productSource,
                  category: i.category,
                  tag: i.tag,
                  unitCost: i.buyingPrice,
                  sellingPrice: i.sellingPrice,
                  orderedQuantity: i.orderedQuantity,
                  deliveredQuantity: i.effectiveQuantity,
                )))
        .toList();

    if (confirmed.isEmpty) {
      ShowMessage.error(context, 'No items to receive in this purchase order.');
      return;
    }

    final totalDeliveredUnits = confirmed.fold<int>(0, (acc, i) => acc + i.deliveredQuantity);
    final confirmedTotal = confirmed.fold<double>(0.0, (acc, i) => acc + (i.unitCost * i.deliveredQuantity));
    final defaultInvoiceNum = widget.purchaseorder.invoiceNumber.isNotEmpty
        ? widget.purchaseorder.invoiceNumber
        : widget.purchaseorder.poNumber;

    final invoiceController = TextEditingController(text: defaultInvoiceNum);
    DateTime invoiceDate = DateTime.now();

    final confirmedByUser = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                  child: Icon(Icons.done_all_rounded, color: Colors.green.shade800, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Receive Everything', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirm that you received ALL ordered stocks without missing items or overpayment.',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Delivered Products', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                            Text('${confirmed.length} items ($totalDeliveredUnits pcs)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Restock Value', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                            Text(_currencyFormat.format(confirmedTotal), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Overpayment Credit', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                            const Text('₱0.00 (None)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Stocks will be added to your physical inventory immediately. Incoming stock allocation will be cleared.',
                            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: invoiceController,
                    decoration: InputDecoration(
                      labelText: 'Invoice / DR Number (Optional)',
                      hintText: 'Enter invoice number if available',
                      prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: invoiceDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDialogState(() => invoiceDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Received Date',
                        prefixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      child: Text(DateFormat('MMM dd, yyyy').format(invoiceDate), style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogCtx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Confirm & Restock', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmedByUser != true || !mounted) return;

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Receiving Full Delivery',
      subtitle: 'Adding stocks to inventory & updating status...',
    );

    final resolvedInvoiceNum = invoiceController.text.trim().isNotEmpty
        ? invoiceController.text.trim()
        : (defaultInvoiceNum.isNotEmpty ? defaultInvoiceNum : 'PO-${DateFormat('yyyyMMdd').format(invoiceDate)}');

    try {
      await _controller.confirmOfficialInvoice(
        context: context,
        purchaseOrderId: widget.purchaseorderID,
        currentOrder: widget.purchaseorder,
        confirmedItems: confirmed,
        missingItems: const [],
        officialInvoiceNumber: resolvedInvoiceNum,
        officialInvoiceAmount: confirmedTotal,
        officialInvoiceDate: invoiceDate,
        pickedImage: null,
      );
      if (mounted) {
        Helperfunctions.showLoading(showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.success(
          context,
          '✅ All stocks received! ${confirmed.length} products ($totalDeliveredUnits units) added to inventory.',
        );
        Navigator.pop(context);
      }
    } catch (e, s) {
      Helperfunctions.showLoading(showLoading: false);
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Receive Everything', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }
  }

  Future<void> onConfirmOfficialInvoice() async {
    final officialInvoiceNum = _officialInvoiceNumberController.text.trim();
    if (officialInvoiceNum.isEmpty) {
      ShowMessage.error(context, 'Please enter or scan the official invoice number.');
      return;
    }

    final double officialAmount = Helperfunctions.formatStringAmountToDouble(_officialInvoiceAmountController.text);

    final List<ConfirmedInvoiceItem> confirmed;
    final List<OrderItem> missing = [];
    int totalDeliveredUnits = 0;
    double confirmedTotal = 0.0;

    if (_comparisonResult != null) {
      confirmed = _comparisonResult!.confirmedItems;
      missing.addAll(_comparisonResult!.missingItems);
      totalDeliveredUnits = _comparisonResult!.totalDeliveredUnits;
      confirmedTotal = officialAmount > 0 ? officialAmount : _comparisonResult!.confirmedTotal;
    } else {
      // Manual confirmation using existing PO items
      confirmed = widget.purchaseorder.items.map((i) {
        return ConfirmedInvoiceItem(
          productId: i.productId,
          productName: i.productName,
          imageUrl: i.imageUrl,
          productSource: i.productSource,
          category: i.category,
          tag: i.tag,
          unitCost: i.buyingPrice,
          sellingPrice: i.sellingPrice,
          orderedQuantity: i.orderedQuantity,
          deliveredQuantity: i.effectiveQuantity,
        );
      }).toList();
      totalDeliveredUnits = confirmed.fold(0, (acc, i) => acc + i.deliveredQuantity);
      confirmedTotal = officialAmount > 0 ? officialAmount : widget.purchaseorder.orderAmount;
    }

    if (confirmed.isEmpty) {
      ShowMessage.error(context, 'No confirmed items. Cannot attach invoice to an empty order.');
      return;
    }

    final double rawOverpayment = widget.purchaseorder.orderAmount - confirmedTotal;
    final double overpayment = rawOverpayment > 0.009 ? double.parse(rawOverpayment.toStringAsFixed(2)) : 0.0;

    // Discrepancy breakdown
    final shortages = _comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.shortage).toList();
    final missingList = _comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.missing).toList();
    final excessList = _comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.excess).toList();

    String msg =
        'Confirm ${confirmed.length} delivered item(s) — $totalDeliveredUnits total units.\n\n'
        '• Invoice No: $officialInvoiceNum\n'
        '• Invoice Date: ${DateFormat('MMM dd, yyyy').format(_officialInvoiceDate)}\n'
        '• Invoiced Total: ${_currencyFormat.format(confirmedTotal)}\n'
        '• Original P.O. Amount: ${_currencyFormat.format(widget.purchaseorder.orderAmount)}\n\n';

    if (shortages.isNotEmpty) {
      msg += '⚠️ Shortages (${shortages.length} items):\n';
      msg += shortages
          .map((s) => '• ${s.productName}: Invoiced ${s.invoicedQuantity} of ${s.orderedQuantity} (Short ${s.differenceQuantity})')
          .join('\n');
      msg += '\n\n';
    }

    if (missingList.isNotEmpty) {
      msg += '❌ Missing / Not Delivered (${missingList.length} items):\n';
      msg += missingList.map((m) => '• ${m.productName} (0 of ${m.orderedQuantity} delivered)').join('\n');
      msg += '\n\n';
    }

    if (excessList.isNotEmpty) {
      msg += '📦 Excess Delivered (${excessList.length} items):\n';
      msg += excessList
          .map((e) => '• ${e.productName}: Invoiced ${e.invoicedQuantity} of ${e.orderedQuantity} (+${e.differenceQuantity})')
          .join('\n');
      msg += '\n\n';
    }

    if (overpayment > 0) {
      msg +=
          '💰 Overpayment Credit: ${_currencyFormat.format(overpayment)}\n'
          'Recorded as credit for dealer to deduct from future purchase orders.';
    } else {
      msg += '✅ Invoiced amounts match — no overpayment credit.';
    }

    final didConfirm = await ShowMessage.confirm(
      context,
      title: 'Attach Invoice & Replenish Stock',
      message: msg,
      icon: Icons.fact_check_outlined,
      confirmText: 'Attach & Replenish',
    );
    if (!didConfirm || !mounted) return;

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Attaching Official Invoice',
      subtitle: 'Replenishing stock & updating supplier records...',
    );

    try {
      await _controller.confirmOfficialInvoice(
        context: context,
        purchaseOrderId: widget.purchaseorderID,
        currentOrder: widget.purchaseorder,
        confirmedItems: confirmed,
        missingItems: missing,
        officialInvoiceNumber: officialInvoiceNum,
        officialInvoiceAmount: confirmedTotal,
        officialInvoiceDate: _officialInvoiceDate,
        pickedImage: _officialInvoiceImages.isNotEmpty ? _officialInvoiceImages.last : null,
      );
      if (mounted) {
        Helperfunctions.showLoading(showLoading: false);
        setState(() => _isSaving = false);
        final repMsg = '✅ Invoice #$officialInvoiceNum attached! ${confirmed.length} products replenished.';
        final misMsg = missing.isNotEmpty ? ' ${missing.length} missing removed.' : '';
        final ovMsg = overpayment > 0 ? ' Credit: ${_currencyFormat.format(overpayment)}.' : '';
        ShowMessage.success(context, '$repMsg$misMsg$ovMsg');
        Navigator.pop(context);
      }
    } catch (e, s) {
      Helperfunctions.showLoading(showLoading: false);
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Confirm Official Invoice', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }
  }

  Future<void> onDelete() async {
    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Deleting Purchase Order',
      subtitle: 'Reverting inventory allocations...',
    );

    try {
      await _controller.deletePurchaseOrder(context: context, purchaseOrderId: widget.purchaseorderID, order: widget.purchaseorder);
      if (mounted) {
        Helperfunctions.showLoading(showLoading: false);
        setState(() => _isSaving = false);
        ShowMessage.success(context, 'Purchase Order deleted.');
        Navigator.pop(context);
      }
    } catch (e, s) {
      Helperfunctions.showLoading(showLoading: false);
      ErrorLogService.logError(page: 'PurchaseorderPage', action: 'Delete PO', error: e, stackTrace: s);
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }
  }

  // ============================================================
  // UI Builder Components
  // ============================================================

  // Purchase Order Details Header Card
  Widget _buildDocumentReconciliationHeader(List<InventoryItem> allInventory) {
    return PoReconciliationHeader(
      isNewRecord: isNewRecord,
      orderNumberController: orderNumberController,
      selectedOrderDate: _selectedOrderDate,
      onPickOrderDate: _pickOrderDate,
      onOrderNumberChanged: (_) => setState(() {}),
      currentListTotalCost: _currentListTotalCost,
      currentListUnits: _currentListUnits,
      currentListCount: _currentListCount,
      showDetailsCard: _showDetailsCard,
      onToggleDetailsCard: () => setState(() => _showDetailsCard = !_showDetailsCard),
      currencyFormat: _currencyFormat,
    );
  }

  // Phase 2 Delivery Section: Collapsible & streamlined to avoid clutter on pending orders
  Widget _buildPhase2DeliverySection(List<InventoryItem> allInventory) {
    final hasInvoiceData = _officialInvoiceImages.isNotEmpty || _officialInvoiceNumberController.text.trim().isNotEmpty || _invoiceLines.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    if (_showPhase2Inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.teal.shade200),
              ),
              color: Colors.teal.withValues(alpha: 0.07),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.document_scanner_outlined, color: Colors.teal, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invoice Reconciler Active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          Text('Scanning or verifying delivered quantities', style: TextStyle(fontSize: 11, color: Colors.teal)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.teal.shade900,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () => setState(() => _showPhase2Inline = false),
                      icon: const Icon(Icons.expand_less, size: 18),
                      label: const Text('Minimize', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildPhase2ConfirmationCard(allInventory),
        ],
      );
    }

    final discrepanciesCount = _comparisonDiscrepancies.where((d) => d.type != PoDiscrepancyType.matched).length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: hasInvoiceData ? Colors.teal.shade300 : colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      color: hasInvoiceData ? Colors.teal.withValues(alpha: 0.04) : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_shipping_outlined, color: Colors.teal, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hasInvoiceData ? 'Invoice Ready' : 'Receive Delivery',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasInvoiceData ? Colors.teal.shade100 : Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hasInvoiceData ? 'In Reconciler' : 'Pending Arrival',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: hasInvoiceData ? Colors.teal.shade900 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasInvoiceData
                            ? '${_invoiceLines.length} items read • $discrepanciesCount discrepancies'
                            : 'When stocks arrive, confirm full delivery or scan the supplier invoice.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      if (hasInvoiceData) {
                        setState(() => _showPhase2Inline = true);
                      } else {
                        _showReceiveDeliveryOptions(allInventory);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: Icon(hasInvoiceData ? Icons.edit_note_rounded : Icons.check_circle_outline_rounded, size: 18),
                    label: Text(
                      hasInvoiceData ? 'Review & Edit Invoice' : 'Receive Delivery',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (hasInvoiceData) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showReceiveDeliveryOptions(allInventory),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    ),
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    label: const Text('Options', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Phase 2 Confirmation Card (when physical stocks arrive)
  Widget _buildPhase2ConfirmationCard(List<InventoryItem> allInventory) {
    return PoPhase2ConfirmationCard(
      comparisonDiscrepancies: _comparisonDiscrepancies,
      officialInvoiceImages: _officialInvoiceImages,
      isComparingWithAi: _isComparingWithAi,
      onShowOfficialInvoiceSourcePicker: _showOfficialInvoiceSourcePicker,
      onReceiveEverything: () => _confirmReceiveEverything(allInventory),
      onRemoveOfficialInvoiceImage: (i) {
        setState(() {
          _officialInvoiceImages.removeAt(i);
        });
        if (_officialInvoiceImages.isNotEmpty) {
          _runOfficialInvoiceExtraction(allInventory);
        } else {
          setState(() {
            _invoiceLines.clear();
            _comparisonDiscrepancies.clear();
            _comparisonResult = null;
            _calculatedOverpayment = 0.0;
          });
        }
      },
      officialInvoiceNumberController: _officialInvoiceNumberController,
      officialInvoiceDate: _officialInvoiceDate,
      onPickOfficialInvoiceDate: _pickOfficialInvoiceDate,
      officialInvoiceAmountController: _officialInvoiceAmountController,
      onInvoiceDetailsChanged: () {
        setState(() {});
        _recomputeDiscrepancies(allInventory);
      },
      calculatedOverpayment: _calculatedOverpayment,
      currencyFormat: _currencyFormat,
      invoiceLines: _invoiceLines,
      invoiceSelectedTab: _invoiceSelectedTab,
      onTabChanged: (tab) => setState(() => _invoiceSelectedTab = tab),
      showMatchedItems: _showMatchedItems,
      onToggleMatchedItems: () => setState(() => _showMatchedItems = !_showMatchedItems),
      onShowCorrectionDialog: (idx, inv, {required bool isInvoice}) => _showCorrectionDialog(idx, inv, isInvoice: isInvoice),
      onQuantityDecrement: (line) {
        if (line.quantity > 1) {
          setState(() => line.quantity--);
          _recomputeDiscrepancies(allInventory);
          final invTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
          _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(invTotal);
        }
      },
      onQuantityIncrement: (line) {
        setState(() => line.quantity++);
        _recomputeDiscrepancies(allInventory);
        final invTotal = _invoiceLines.fold(0.0, (acc, l) => acc + l.lineTotal);
        _officialInvoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(invTotal);
      },
      onAddMissingLine: (inv, {required bool isInvoice}) => _showAddMissingLineDialog(inv, isInvoice: isInvoice),
      allInventory: allInventory,
    );
  }

  // Phase 3 Confirmed / Invoiced Status Card
  Widget _buildConfirmedStatusCard() {
    return PoConfirmedStatusCard(purchaseorder: widget.purchaseorder, currencyFormat: _currencyFormat);
  }

  Future<void> _pickOrderDate() async {
    final picked = await showDatePicker(context: context, initialDate: _selectedOrderDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (picked != null) setState(() => _selectedOrderDate = picked);
  }

  Future<void> _pickOfficialInvoiceDate() async {
    final picked = await showDatePicker(context: context, initialDate: _officialInvoiceDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (picked != null) setState(() => _officialInvoiceDate = picked);
  }

  // Recommendations Banner for Products with Pre-Order Stock Deficits & Low Stock Alerts
  Widget _buildPreOrderRecommendationsBanner(List<InventoryItem> allInventory, ColorScheme colorScheme) {
    final recommendedItems = allInventory.where((i) => i.isPreOrderRecommended).toList();
    if (recommendedItems.isEmpty) return const SizedBox.shrink();

    final totalRecommendedUnits = recommendedItems.fold<int>(0, (acc, i) => acc + i.recommendedPreOrderOrderQuantity);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: const Color(0xFF6D28D9).withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.star_rounded, color: Color(0xFF6D28D9), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pre-Order Restock (${recommendedItems.length} items)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5B21B6)),
                    ),
                    Text(
                      '$totalRecommendedUnits units needed for booked customer orders',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _addOrUpdatePreOrderLines(recommendedItems, allInventory),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                child: const Text('Add All'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: Icon(_showPreOrderChips ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: const Color(0xFF6D28D9)),
                onPressed: () => setState(() => _showPreOrderChips = !_showPreOrderChips),
              ),
            ],
          ),
          if (_showPreOrderChips) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recommendedItems.map((item) {
                final label = item.hasPreOrderShortage
                    ? '${item.productName}: +${item.preOrderShortage}'
                    : '${item.productName}: +${item.recommendedPreOrderOrderQuantity}';
                return ActionChip(
                  backgroundColor: Colors.white,
                  side: BorderSide(color: const Color(0xFF6D28D9).withValues(alpha: 0.3)),
                  avatar: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF6D28D9)),
                  label: Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5B21B6)),
                  ),
                  onPressed: () => _addOrUpdatePreOrderLines([item], allInventory),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // Single Item Card in the Document-Ordered List
  Widget _buildDocumentLineCard(int index, PoExtractedLine line, ColorScheme colorScheme, List<InventoryItem> allInventory) {
    InventoryItem? matchedItem;
    for (final item in allInventory) {
      if (item.id == line.productId || item.productName.trim().toLowerCase() == line.productName.trim().toLowerCase()) {
        matchedItem = item;
        break;
      }
    }

    return PoDocumentLineCard(
      key: ValueKey('doc_line_${line.productId}_$index'),
      index: index,
      line: line,
      inventoryItem: matchedItem,
      currencyFormat: _currencyFormat,
      onToggleFlag: () => setState(() => line.isIncorrect = !line.isIncorrect),
      onCorrect: () => _showCorrectionDialog(index, allInventory),
    );
  }

  // Sticky Bottom Bar
  Widget _buildStickyBottomBar(List<InventoryItem> allInventory) {
    final colorScheme = Theme.of(context).colorScheme;

    // Phase 2: pending PO confirmation
    if (_isEditing && _isPending) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: Colors.teal.withValues(alpha: 0.4))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AsyncOutlinedButton.icon(
                      onPressed: () async {
                        if (await ShowMessage.confirm(
                          context,
                          title: 'Delete PO',
                          message: 'Delete this pending PO? No inventory was changed.',
                          isDestructive: true,
                          icon: Icons.delete_outline,
                          confirmText: 'Delete',
                        )) {
                          await onDelete();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (context) {
                        final hasInvoice =
                            _invoiceLines.isNotEmpty || _comparisonResult != null || _officialInvoiceNumberController.text.trim().isNotEmpty;
                        return AsyncFilledButton.icon(
                          onPressed: hasInvoice
                              ? onConfirmOfficialInvoice
                              : () async => _showReceiveDeliveryOptions(allInventory),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(hasInvoice ? Icons.fact_check_outlined : Icons.local_shipping_outlined),
                          label: Text(
                            hasInvoice
                                ? 'Attach Invoice & Replenish'
                                : 'Receive Delivery',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AsyncOutlinedButton.icon(
                  onPressed: onUpdatePending,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Update Verified Order Items', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Phase 3: confirmed PO (read-only)
    if (_isEditing && _isConfirmed) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          ),
          child: AsyncOutlinedButton.icon(
            onPressed: () async {
              if (await ShowMessage.confirm(
                context,
                title: 'Delete Purchase Order',
                message: 'Delete this confirmed PO? Replenished stock will be reverted.',
                isDestructive: true,
                icon: Icons.delete_outline,
                confirmText: 'Delete',
              )) {
                await onDelete();
              }
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Purchase Order', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    // Phase 1: New PO creation
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_currentListCount SKUs • $_currentListUnits units', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    if (_totalSelectedOverpayments > 0)
                      Text(
                        'Net after credit: ${_currencyFormat.format(_guidedNetAmount)}',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFormat.format(_currentListTotalCost),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colorScheme.primary),
                    ),
                    Text('Total Amount', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            AsyncFilledButton.icon(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Colors.orange.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Save Purchase Order (Pending)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLocked = _isSaving || _isComparingWithAi;

    // Phase 3: confirmed / invoiced PO (read-only view)
    if (_isEditing && _isConfirmed) {
      final poRef = widget.purchaseorder.poNumber.isNotEmpty ? widget.purchaseorder.poNumber : widget.purchaseorder.invoiceNumber;
      final invRef = widget.purchaseorder.invoiceNumber.isNotEmpty ? ' • Inv: ${widget.purchaseorder.invoiceNumber}' : '';
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (isLocked) {
            ShowMessage.warning(context, 'Operation in progress. Please wait.');
          } else {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: CustomAppbar(
            title: 'Purchase Order',
            subtitle: 'Invoiced — $poRef$invRef',
            onBackPressed: isLocked ? () => ShowMessage.warning(context, 'Operation in progress. Please wait.') : null,
          ),
          bottomNavigationBar: ScreenSize.isTabletLandscape(context) ? null : _buildStickyBottomBar([]),
          body: ScreenSize.isTabletLandscape(context)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        primary: false,
                        child: _buildConfirmedStatusCard(),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border(
                            left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                primary: false,
                                padding: const EdgeInsets.all(16),
                                child: AuditHistoryWidget(
                                  createdBy: widget.purchaseorder.createdBy,
                                  createdDate: widget.purchaseorder.createdDate,
                                  createdPage: widget.purchaseorder.createdPage,
                                  lastUpdatedBy: widget.purchaseorder.lastUpdatedBy,
                                  lastUpdatedDate: widget.purchaseorder.lastupdatedDate,
                                  lastUpdatedPage: widget.purchaseorder.lastUpdatedPage,
                                ),
                              ),
                            ),
                            _buildStickyBottomBar([]),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildConfirmedStatusCard(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: AuditHistoryWidget(
                          createdBy: widget.purchaseorder.createdBy,
                          createdDate: widget.purchaseorder.createdDate,
                          createdPage: widget.purchaseorder.createdPage,
                          lastUpdatedBy: widget.purchaseorder.lastUpdatedBy,
                          lastUpdatedDate: widget.purchaseorder.lastupdatedDate,
                          lastUpdatedPage: widget.purchaseorder.lastUpdatedPage,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (isLocked) {
          ShowMessage.warning(context, 'Operation in progress. Please wait.');
          return;
        }
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have unsaved changes on this purchase order. Are you sure you want to go back and discard them?',
            confirmText: 'Discard',
            cancelText: 'Keep Editing',
            isDestructive: true,
            icon: Icons.warning_amber_rounded,
          );
          if (shouldDiscard && context.mounted) {
            Navigator.pop(context);
          }
        } else {
          Navigator.pop(context);
        }
      },
      child: StreamBuilder<List<InventoryItem>>(
        stream: _inventoryStream,
        builder: (context, snapshot) {
          // Purchase Orders are strictly exclusive to Selecta products.
          // Other products are completely excluded from PO catalog matching, suggestions, and discrepancy analysis.
          final allInventory = (snapshot.data ?? []).where((item) => item.source == InventoryProductSource.selecta).toList();

          if (widget.initialLines != null && !_hasPrioritizedInitialLines && allInventory.isNotEmpty && _documentLines.isNotEmpty) {
            _hasPrioritizedInitialLines = true;
            _prioritizePreOrderDeficitLines(allInventory);
          }

          if (widget.initialOpenManualPicker && !_hasTriggeredInitialManualPicker && allInventory.isNotEmpty && _documentLines.isEmpty) {
            _hasTriggeredInitialManualPicker = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _openManualPoPicker(allInventory);
              }
            });
          }

          return Scaffold(
            appBar: CustomAppbar(
              title: 'Purchase Order',
              subtitle: isNewRecord ? 'New Purchase Order' : '🟡 Pending Delivery',
              onBackPressed: isLocked ? () => ShowMessage.warning(context, 'Operation in progress. Please wait.') : null,
            ),
            bottomNavigationBar: ScreenSize.isTabletLandscape(context) ? null : _buildStickyBottomBar(allInventory),
            body: ScreenSize.isTabletLandscape(context)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Pane: Document Reconciliation, Delivery Details, and Controls
                      Expanded(
                        flex: 5,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              right: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  primary: false,
                                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildDocumentReconciliationHeader(allInventory),
                                      if (_isEditing && _isPending) _buildPhase2DeliverySection(allInventory),
                                      _buildPreOrderRecommendationsBanner(allInventory, colorScheme),
                                      if (_unsettledOverpayments.isNotEmpty && isNewRecord)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                          child: _buildOverpaymentCard(),
                                        ),
                                      if (!isNewRecord)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                          child: AuditHistoryWidget(
                                            createdBy: widget.purchaseorder.createdBy,
                                            createdDate: widget.purchaseorder.createdDate,
                                            createdPage: widget.purchaseorder.createdPage,
                                            lastUpdatedBy: widget.purchaseorder.lastUpdatedBy,
                                            lastUpdatedDate: widget.purchaseorder.lastupdatedDate,
                                            lastUpdatedPage: widget.purchaseorder.lastUpdatedPage,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildStickyBottomBar(allInventory),
                            ],
                          ),
                        ),
                      ),
                      // Right Pane: Order Lines & Fast Actions
                      Expanded(
                        flex: 5,
                        child: _buildTabletPoLinesPanel(colorScheme, allInventory),
                      ),
                    ],
                  )
                : CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // Document Reconciliation Header
                SliverToBoxAdapter(child: _buildDocumentReconciliationHeader(allInventory)),

                // Phase 2 Delivery Section (if existing pending PO)
                if (_isEditing && _isPending) SliverToBoxAdapter(child: _buildPhase2DeliverySection(allInventory)),

                // Pre-Order Shortage Recommendations Banner
                SliverToBoxAdapter(child: _buildPreOrderRecommendationsBanner(allInventory, colorScheme)),

                // If no items added yet: Prompt to select catalog products
                if (_documentLines.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Icon(Icons.inventory_2_outlined, size: 44, color: colorScheme.primary),
                            ),
                            const SizedBox(height: 16),
                            const Text('Start Your Purchase Order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(
                              'Select products from your catalog or generate restock suggestions based on inventory levels.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: () => _openManualPoPicker(allInventory),
                                  icon: const Icon(Icons.add_shopping_cart_rounded),
                                  label: const Text('Browse Catalog', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _openAutomatedPoSuggestions(allInventory),
                                  icon: const Icon(Icons.auto_awesome_rounded),
                                  label: const Text('Auto-Suggest P.O.', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Section Header for Document Lines (Collapsible)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: InkWell(
                        onTap: () => setState(() => _showItemsList = !_showItemsList),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.format_list_numbered_rounded, size: 16, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Order Items (${_documentLines.length})',
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$_currentListUnits units',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _currencyFormat.format(_currentListTotalCost),
                                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _showItemsList ? 'Hide' : 'Show',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                _showItemsList ? Icons.expand_less : Icons.expand_more,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Extracted Document Lines List (Numbered in exact document sequence) - Collapsible
                  if (_showItemsList)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildDocumentLineCard(index, _documentLines[index], colorScheme, allInventory);
                        }, childCount: _documentLines.length),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 8),
                    ),
                ],

                // Overpayment deduction selector (if unsettled overpayments exist)
                if (_unsettledOverpayments.isNotEmpty && isNewRecord)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildOverpaymentCard(),
                    ),
                  ),

                if (!isNewRecord)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: AuditHistoryWidget(
                        createdBy: widget.purchaseorder.createdBy,
                        createdDate: widget.purchaseorder.createdDate,
                        createdPage: widget.purchaseorder.createdPage,
                        lastUpdatedBy: widget.purchaseorder.lastUpdatedBy,
                        lastUpdatedDate: widget.purchaseorder.lastupdatedDate,
                        lastUpdatedPage: widget.purchaseorder.lastUpdatedPage,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverpaymentCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.savings_outlined, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                const Text('Apply Existing Overpayment Credit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              ],
            ),
            const Divider(height: 12),
            ..._unsettledOverpayments.map((doc) {
              final order = doc.data();
              final isChecked = _selectedOverpaymentIds.contains(doc.id);
              final label = order.invoiceNumber.isNotEmpty
                  ? order.invoiceNumber
                  : 'Date: ${Helperfunctions.formatTimestampForDisplay(order.orderDate)}';
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: isChecked,
                title: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Credit: ${_currencyFormat.format(order.overpayment)}',
                  style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                ),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedOverpaymentIds.add(doc.id);
                  } else {
                    _selectedOverpaymentIds.remove(doc.id);
                  }
                }),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletPoLinesPanel(ColorScheme colorScheme, List<InventoryItem> allInventory) {
    if (_documentLines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.inventory_2_outlined, size: 44, color: colorScheme.primary),
              ),
              const SizedBox(height: 16),
              const Text('Start Your Purchase Order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Select products from your catalog or generate restock suggestions based on inventory levels.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openManualPoPicker(allInventory),
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: const Text('Browse Catalog', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _openAutomatedPoSuggestions(allInventory),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Auto-Suggest P.O.', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Top Action Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Items (${_documentLines.length} SKUs, $_currentListUnits pcs)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      'Total Cost: ${_currencyFormat.format(_currentListTotalCost)}',
                      style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openAutomatedPoSuggestions(allInventory),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Auto-Suggest', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openManualPoPicker(allInventory),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Items', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        // Scrollable Line Items
        Expanded(
          child: ListView.builder(
            primary: false,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _documentLines.length,
            itemBuilder: (context, index) {
              return _buildDocumentLineCard(index, _documentLines[index], colorScheme, allInventory);
            },
          ),
        ),
      ],
    );
  }
}
