import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/controllers/purchaseorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/data/responsive.dart';

/// Full-page product catalog for restock / Purchase Orders.
///
/// Provides dealers with an expansive, dedicated interface to browse products,
/// search, filter categories (Best Sellers, By Case, By Piece, Pre-order shortages),
/// and set purchase order quantities efficiently without the vertical constraints
/// and accidental dismissal issues of modal bottom sheets.
class PurchaseOrderCatalogPage extends StatefulWidget {
  final List<InventoryItem>? allInventory;
  final List<PoExtractedLine> existingLines;
  final bool isDirectCreationFlow;

  final InventoryController? inventoryController;
  final PurchaseOrderController? purchaseOrderController;

  const PurchaseOrderCatalogPage({
    super.key,
    this.allInventory,
    this.existingLines = const [],
    this.isDirectCreationFlow = true,
    this.inventoryController,
    this.purchaseOrderController,
  });

  @override
  State<PurchaseOrderCatalogPage> createState() => _PurchaseOrderCatalogPageState();
}

class _PurchaseOrderCatalogPageState extends State<PurchaseOrderCatalogPage> {
  late final InventoryController? _inventoryController;
  PurchaseOrderController? _poControllerInstance;
  PurchaseOrderController get _poController =>
      widget.purchaseOrderController ?? (_poControllerInstance ??= PurchaseOrderController());
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  final Map<String, int> _selectedQuantities = {};
  /// Tracks the exact order in which products had quantity added (FIFO / Add-to-cart sorting).
  final List<String> _addedProductIdsOrder = [];
  List<QueryDocumentSnapshot<Purchaseorder>> _unsettledOverpayments = [];
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.allInventory == null) {
      _inventoryController = widget.inventoryController ?? InventoryController();
    } else {
      _inventoryController = widget.inventoryController;
    }
    for (final line in widget.existingLines) {
      if (line.quantity > 0) {
        _selectedQuantities[line.productId] = line.quantity;
        if (!_addedProductIdsOrder.contains(line.productId)) {
          _addedProductIdsOrder.add(line.productId);
        }
      }
    }
    _loadUnsettledOverpayments();
  }

  Future<void> _loadUnsettledOverpayments() async {
    try {
      final records = await _poController.getUnsettledOverpayments();
      if (mounted) {
        setState(() => _unsettledOverpayments = records);
      }
    } catch (_) {}
  }

  /// Updates a product's quantity while tracking chronological add-to-cart order.
  void _updateQuantity(String productId, int newQty) {
    setState(() {
      if (newQty <= 0) {
        _selectedQuantities.remove(productId);
        _addedProductIdsOrder.remove(productId);
      } else {
        if (!_selectedQuantities.containsKey(productId) || _selectedQuantities[productId] == 0) {
          if (!_addedProductIdsOrder.contains(productId)) {
            _addedProductIdsOrder.add(productId);
          }
        }
        _selectedQuantities[productId] = newQty;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
  }

  Future<void> _promptDirectQuantityDialog(InventoryItem item) async {
    final currentQty = _selectedQuantities[item.id] ?? 0;
    final initialText = currentQty > 0 ? '$currentQty' : '';
    final controller = TextEditingController(text: initialText)..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(item.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buying Cost: ${_currencyFormat.format(item.buyingPrice)} • On-hand: ${item.stockQuantity} pcs',
                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Order Quantity (pcs)',
                  hintText: 'Enter quantity',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => controller.clear()),
                ),
                onSubmitted: (val) {
                  final qty = int.tryParse(val.trim()) ?? 0;
                  Navigator.pop(ctx, qty);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim()) ?? 0;
                Navigator.pop(ctx, qty);
              },
              child: const Text('Set Quantity'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      _updateQuantity(item.id, result);
    }
  }

  List<PoExtractedLine> _buildOrderLines(List<InventoryItem> allInventory) {
    final Map<String, InventoryItem> invMap = {for (final i in allInventory) i.id: i};
    final List<PoExtractedLine> result = [];

    // Strictly order based on the chronological sequence products were added to cart (FIFO)
    for (final productId in _addedProductIdsOrder) {
      final qty = _selectedQuantities[productId] ?? 0;
      final item = invMap[productId];
      if (qty > 0 && item != null) {
        result.add(
          PoExtractedLine(
            productId: item.id,
            productName: item.productName,
            imageUrl: item.imageUrl,
            productSource: item.source.key,
            category: item.category,
            tag: item.tag,
            buyingPrice: item.buyingPrice,
            sellingPrice: item.sellingPrice,
            quantity: qty,
            rawDocText: item.productName,
          ),
        );
      }
    }

    // Safety fallback for any items in _selectedQuantities that were not in _addedProductIdsOrder
    for (final entry in _selectedQuantities.entries) {
      if (entry.value > 0 && !result.any((r) => r.productId == entry.key)) {
        final item = invMap[entry.key];
        if (item != null) {
          result.add(
            PoExtractedLine(
              productId: item.id,
              productName: item.productName,
              imageUrl: item.imageUrl,
              productSource: item.source.key,
              category: item.category,
              tag: item.tag,
              buyingPrice: item.buyingPrice,
              sellingPrice: item.sellingPrice,
              quantity: entry.value,
              rawDocText: item.productName,
            ),
          );
        }
      }
    }

    return result;
  }

  void _onSubmit(List<InventoryItem> allInventory) {
    final lines = _buildOrderLines(allInventory);

    if (widget.isDirectCreationFlow) {
      if (lines.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('No Items Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: const Text(
              'You have not selected any products yet.\n\nPlease add products to your purchase order before proceeding.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      _showConfirmationBottomSheet(lines);
    } else {
      Navigator.pop(context, lines);
    }
  }

  void _showConfirmationBottomSheet(List<PoExtractedLine> lines) {
    final poNumberController = TextEditingController(
      text: 'PO-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}',
    );
    DateTime selectedDate = DateTime.now();
    final Set<String> selectedOverpaymentIds = {};
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorScheme = Theme.of(context).colorScheme;
            final totalUnits = lines.fold<int>(0, (acc, l) => acc + l.quantity);
            final grossCost = lines.fold<double>(0.0, (acc, l) => acc + (l.buyingPrice * l.quantity));
            final totalDeductions = _poController.calculateTotalSelectedOverpayments(
              unsettledDocs: _unsettledOverpayments,
              selectedIds: selectedOverpaymentIds,
            );
            final netPayable = (grossCost - totalDeductions) > 0 ? (grossCost - totalDeductions) : 0.0;

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Confirm Purchase Order',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${lines.length} items • $totalUnits units (FIFO sorted)',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: isSaving ? null : () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Scrollable Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── P.O. Details (Number & Date) ─────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: poNumberController,
                                  decoration: InputDecoration(
                                    labelText: 'P.O. Number',
                                    prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                                    suffixIcon: poNumberController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 16),
                                            onPressed: () {
                                              poNumberController.clear();
                                              setModalState(() {});
                                            },
                                          )
                                        : null,
                                    filled: true,
                                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  ),
                                  onChanged: (_) => setModalState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: sheetContext,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2035),
                                    );
                                    if (picked != null) {
                                      setModalState(() => selectedDate = picked);
                                    }
                                  },
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded, size: 16, color: colorScheme.primary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            DateFormat('MMM dd, yyyy').format(selectedDate),
                                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Ordered Products (FIFO / Add-to-Cart Order) ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order Items (Added Order)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${lines.length} items',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: lines.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                indent: 56,
                                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                              itemBuilder: (context, index) {
                                final line = lines[index];
                                final lineTotal = line.buyingPrice * line.quantity;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      // Item number badge
                                      Container(
                                        width: 20,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      CachedProductImage(imageUrl: line.imageUrl, size: 38, borderRadius: 8),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              line.productName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_currencyFormat.format(line.buyingPrice)} × ${line.quantity} pcs',
                                              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _currencyFormat.format(lineTotal),
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Overpayment Credit Deductions (if any exist) ──
                          if (_unsettledOverpayments.isNotEmpty) ...[
                            Text(
                              'Available Overpayment Credits',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Material(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
                                child: Column(
                                  children: _unsettledOverpayments.map((doc) {
                                    final order = doc.data();
                                    final isChecked = selectedOverpaymentIds.contains(doc.id);
                                    final label = order.invoiceNumber.isNotEmpty ? 'Inv #${order.invoiceNumber}' : 'PO #${order.poNumber}';
                                    return CheckboxListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      dense: true,
                                      title: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                      subtitle: Text(
                                        'Credit: ${_currencyFormat.format(order.overpayment)} • ${DateFormat('MMM dd, yyyy').format(order.orderDate.toDate())}',
                                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                      ),
                                      value: isChecked,
                                      onChanged: (val) {
                                        setModalState(() {
                                          if (val == true) {
                                            selectedOverpaymentIds.add(doc.id);
                                          } else {
                                            selectedOverpaymentIds.remove(doc.id);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // ── Financial Breakdown Card ───────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Gross Order Amount', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                                    Text(_currencyFormat.format(grossCost), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                if (totalDeductions > 0) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Overpayment Credits Applied', style: TextStyle(fontSize: 12.5, color: Colors.green.shade700)),
                                      Text('- ${_currencyFormat.format(totalDeductions)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                                    ],
                                  ),
                                ],
                                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Net Order Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    Text(
                                      _currencyFormat.format(netPayable),
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom Action Buttons ───────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
                    ),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: isSaving ? null : () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Edit Items'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    setModalState(() => isSaving = true);
                                    await _saveOrderDirectly(
                                      sheetContext: sheetContext,
                                      lines: lines,
                                      poNumber: poNumberController.text,
                                      orderDate: selectedDate,
                                      selectedOverpaymentIds: selectedOverpaymentIds,
                                      onFailure: () {
                                        if (sheetContext.mounted) {
                                          setModalState(() => isSaving = false);
                                        }
                                      },
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Confirm & Create Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveOrderDirectly({
    required BuildContext sheetContext,
    required List<PoExtractedLine> lines,
    required String poNumber,
    required DateTime orderDate,
    required Set<String> selectedOverpaymentIds,
    required VoidCallback onFailure,
  }) async {
    final cleanPoNumber = poNumber.trim().toUpperCase();
    if (cleanPoNumber.isEmpty) {
      ShowMessage.error(sheetContext, 'Please enter a valid P.O. Number.');
      onFailure();
      return;
    }

    final items = lines.map((l) {
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

    final grossCost = lines.fold<double>(0.0, (acc, l) => acc + (l.buyingPrice * l.quantity));

    try {
      await _poController.savePurchaseOrder(
        context: context,
        orderAmount: grossCost,
        selectedOrderDate: orderDate,
        pickedImage: null,
        selectedOverpaymentIds: selectedOverpaymentIds,
        unsettledOverpayments: _unsettledOverpayments,
        items: items,
        poNumber: cleanPoNumber,
      );

      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      if (mounted) {
        Navigator.pop(context);
        ShowMessage.success(context, 'Purchase order $cleanPoNumber created successfully.');
      }
    } catch (e, stack) {
      ErrorLogService.logError(
        page: AppPages.purchaseOrder,
        action: 'Save Purchase Order Direct',
        error: e,
        stackTrace: stack,
      );
      if (sheetContext.mounted) {
        ShowMessage.error(sheetContext, 'Failed to create purchase order: $e');
      }
      onFailure();
    }
  }

  void _addAllRecommendedPreOrders(List<InventoryItem> items) {
    HapticFeedback.mediumImpact();
    for (final item in items) {
      final neededQty = item.recommendedPreOrderOrderQuantity > 0 ? item.recommendedPreOrderOrderQuantity : 1;
      final current = _selectedQuantities[item.id] ?? 0;
      if (current < neededQty) {
        _updateQuantity(item.id, neededQty);
      }
    }
    ShowMessage.success(context, 'Added recommended quantities for ${items.length} shortage product(s).');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allInventory != null) {
      final selectaOnly = widget.allInventory!.where((i) => i.source == InventoryProductSource.selecta).toList();
      return _buildScaffold(context, selectaOnly);
    }

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryController?.getActiveInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(
            appBar: CustomAppbar(
              title: widget.isDirectCreationFlow ? 'Restock Catalog' : 'Manual Purchase Order',
              subtitle: widget.isDirectCreationFlow ? 'Select products & quantities for Purchase Order' : 'Update Purchase Order Items',
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final allInventory = (snapshot.data ?? []).where((i) => i.source == InventoryProductSource.selecta).toList();

        return _buildScaffold(context, allInventory);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, List<InventoryItem> allInventory) {
    // Filter items according to search query
    final selectaCatalog = allInventory.where((i) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.productName.toLowerCase().contains(q) || i.itemCode.toLowerCase().contains(q);
    }).toList();

    // Grouping: Sort only by case (by SRP) then by piece (by SRP)
    final caseProducts = selectaCatalog.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = selectaCatalog.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final bestSellerProducts = selectaCatalog.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);

    // Recommended Pre-Orders: Products where pre-orders exceed warehouse stock (shortage)
    // or leave remaining stock at or below lowStockThreshold
    final recommendedPreOrders = selectaCatalog.where((i) => i.isPreOrderRecommended).toList()
      ..sort((a, b) {
        if (a.hasPreOrderShortage && !b.hasPreOrderShortage) return -1;
        if (!a.hasPreOrderShortage && b.hasPreOrderShortage) return 1;
        if (a.hasPreOrderShortage && b.hasPreOrderShortage) {
          final defA = a.preOrderShortage;
          final defB = b.preOrderShortage;
          if (defB != defA) return defB.compareTo(defA);
        } else {
          final remA = a.remainingStockAfterPreOrder;
          final remB = b.remainingStockAfterPreOrder;
          if (remA != remB) return remA.compareTo(remB);
        }
        return _compareProducts(a, b);
      });

    final Map<String, InventoryItem> invMap = {for (final i in allInventory) i.id: i};
    int totalSkus = 0;
    int totalUnits = 0;
    double totalCost = 0.0;

    _selectedQuantities.forEach((id, qty) {
      if (qty > 0) {
        totalSkus++;
        totalUnits += qty;
        final inv = invMap[id];
        if (inv != null) {
          totalCost += qty * inv.buyingPrice;
        }
      }
    });

    final hasSelectedItems = _selectedQuantities.values.any((qty) => qty > 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (hasSelectedItems) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Selections?',
            message: 'You have selected products in the catalog. Are you sure you want to go back and discard your selections?',
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
      child: Scaffold(
        appBar: CustomAppbar(
          title: widget.isDirectCreationFlow ? 'Restock Catalog' : 'Manual Purchase Order',
          subtitle: widget.isDirectCreationFlow ? 'Restock from Selecta • Select Products' : 'Update Purchase Order Items',
        ),
        bottomNavigationBar: ScreenSize.isTabletLandscape(context)
            ? null
            : _buildStickyBottomBar(
                context: context,
                totalSkus: totalSkus,
                totalUnits: totalUnits,
                totalCost: totalCost,
                allInventory: allInventory,
              ),
        body: ScreenSize.isTabletLandscape(context)
            ? _buildTabletLandscapeView(
                context: context,
                allInventory: allInventory,
                selectaCatalog: selectaCatalog,
                recommendedPreOrders: recommendedPreOrders,
                caseProducts: caseProducts,
                pieceProducts: pieceProducts,
                bestSellerProducts: bestSellerProducts,
                totalSkus: totalSkus,
                totalUnits: totalUnits,
                totalCost: totalCost,
                invMap: invMap,
              )
            : _buildCatalogContent(
                context: context,
                selectaCatalog: selectaCatalog,
                recommendedPreOrders: recommendedPreOrders,
                caseProducts: caseProducts,
                pieceProducts: pieceProducts,
                bestSellerProducts: bestSellerProducts,
              ),
      ),
    );
  }

  Widget _buildTabletLandscapeView({
    required BuildContext context,
    required List<InventoryItem> allInventory,
    required List<InventoryItem> selectaCatalog,
    required List<InventoryItem> recommendedPreOrders,
    required List<InventoryItem> caseProducts,
    required List<InventoryItem> pieceProducts,
    required List<InventoryItem> bestSellerProducts,
    required int totalSkus,
    required int totalUnits,
    required double totalCost,
    required Map<String, InventoryItem> invMap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Product Catalog (flex: 6)
        Expanded(
          flex: 6,
          child: _buildCatalogContent(
            context: context,
            selectaCatalog: selectaCatalog,
            recommendedPreOrders: recommendedPreOrders,
            caseProducts: caseProducts,
            pieceProducts: pieceProducts,
            bestSellerProducts: bestSellerProducts,
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Right: Order Summary & Review (flex: 4)
        Expanded(
          flex: 4,
          child: _buildTabletCartPane(
            context: context,
            allInventory: allInventory,
            totalSkus: totalSkus,
            totalUnits: totalUnits,
            totalCost: totalCost,
            invMap: invMap,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletCartPane({
    required BuildContext context,
    required List<InventoryItem> allInventory,
    required int totalSkus,
    required int totalUnits,
    required double totalCost,
    required Map<String, InventoryItem> invMap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedProductIds = _addedProductIdsOrder.where((id) => (_selectedQuantities[id] ?? 0) > 0).toList();

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            color: colorScheme.surface,
            child: Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Order Cart ($totalSkus SKU${totalSkus == 1 ? '' : 's'} • $totalUnits units)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selectedProductIds.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final confirmed = await ShowMessage.confirm(
                        context,
                        title: 'Clear Selections',
                        message: 'Are you sure you want to clear all product quantities?',
                        confirmText: 'Clear All',
                        isDestructive: true,
                      );
                      if (confirmed && mounted) {
                        setState(() {
                          _selectedQuantities.clear();
                          _addedProductIdsOrder.clear();
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Restock PO Meta Card
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surface,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isDirectCreationFlow ? 'Restock Purchase Order' : 'Manual P.O. Selection',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isDirectCreationFlow
                              ? 'Target: Direct Factory Order from Selecta'
                              : 'Updating Purchase Order lines',
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Selected Items List
          Expanded(
            child: selectedProductIds.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'No items in order',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select products on the left to add to Purchase Order.',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: selectedProductIds.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final id = selectedProductIds[index];
                      final item = invMap[id];
                      final qty = _selectedQuantities[id] ?? 0;
                      if (item == null) return const SizedBox.shrink();
                      final itemTotal = item.buyingPrice * qty;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CachedProductImage(imageUrl: item.imageUrl, size: 40, borderRadius: 8),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_currencyFormat.format(item.buyingPrice)} / unit',
                                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Stepper
                            Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 14),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _updateQuantity(item.id, qty - 1);
                                    },
                                  ),
                                  InkWell(
                                    onTap: () => _promptDirectQuantityDialog(item),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        '$qty',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 14),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      _updateQuantity(item.id, qty + 1);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 70,
                              child: Text(
                                _currencyFormat.format(itemTotal),
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Sticky Cart Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Units:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                    Text('$totalUnits', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Buying Cost:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      _currencyFormat.format(totalCost),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(widget.isDirectCreationFlow ? Icons.receipt_long_rounded : Icons.check_rounded, size: 20),
                    label: Text(
                      widget.isDirectCreationFlow
                          ? (totalUnits > 0 ? 'Create Order ($totalUnits)' : 'Create Order')
                          : 'Apply to P.O. ($totalUnits)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _onSubmit(allInventory),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogContent({
    required BuildContext context,
    required List<InventoryItem> selectaCatalog,
    required List<InventoryItem> recommendedPreOrders,
    required List<InventoryItem> caseProducts,
    required List<InventoryItem> pieceProducts,
    required List<InventoryItem> bestSellerProducts,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Search Bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search Selecta products or codes...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),

        // ── Category Filter Chips ────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              _buildFilterChip('all', 'All Products (${selectaCatalog.length})', Icons.grid_view_rounded),
              if (recommendedPreOrders.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildFilterChip(
                  'recommended',
                  'Recommended (${recommendedPreOrders.length})',
                  Icons.auto_awesome_rounded,
                  const Color(0xFF7C3AED),
                ),
              ],
              const SizedBox(width: 8),
              _buildFilterChip('by_case', 'By Case (${caseProducts.length})', Icons.all_inbox_rounded, Colors.orange.shade800),
              const SizedBox(width: 8),
              _buildFilterChip('by_piece', 'By Piece (${pieceProducts.length})', Icons.icecream_outlined, colorScheme.primary),
              if (bestSellerProducts.isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildFilterChip('best_sellers', 'Best Sellers (${bestSellerProducts.length})', Icons.star_rounded, Colors.amber.shade700),
              ],
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Grouped Product Catalog List ─────────────────────────────
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // 1. Recommended Pre-Orders placed at the VERY TOP
              if (_selectedCategory == 'all' || _selectedCategory == 'recommended')
                if (recommendedPreOrders.isNotEmpty) ...[
                  _buildSliverHeader(
                    'Recommended Pre-Orders',
                    recommendedPreOrders.length,
                    Icons.auto_awesome_rounded,
                    const Color(0xFF7C3AED),
                    trailing: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFF7C3AED),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 14),
                      label: const Text('Add All Shortages', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => _addAllRecommendedPreOrders(recommendedPreOrders),
                    ),
                  ),
                  _buildSliverProductList(recommendedPreOrders),
                ],

              // 2. By Case (sorted by SRP)
              if (_selectedCategory == 'all' || _selectedCategory == 'by_case')
                if (caseProducts.isNotEmpty) ...[
                  _buildSliverHeader('By Case', caseProducts.length, Icons.all_inbox_rounded, const Color(0xFFEA580C)),
                  _buildSliverProductList(caseProducts),
                ],

              // 3. By Piece (sorted by SRP)
              if (_selectedCategory == 'all' || _selectedCategory == 'by_piece')
                if (pieceProducts.isNotEmpty) ...[
                  _buildSliverHeader('By Piece', pieceProducts.length, Icons.icecream_outlined, colorScheme.primary),
                  _buildSliverProductList(pieceProducts),
                ],

              // 4. Best Sellers (only if explicitly filtered)
              if (_selectedCategory == 'best_sellers')
                if (bestSellerProducts.isNotEmpty) ...[
                  _buildSliverHeader('Best Sellers', bestSellerProducts.length, Icons.star_rounded, const Color(0xFFD97706)),
                  _buildSliverProductList(bestSellerProducts),
                ],

              if (selectaCatalog.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? 'No products match "$_searchQuery"' : 'No Selecta products found',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon, [Color? iconColor]) {
    final isSelected = _selectedCategory == key;
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : (iconColor ?? colorScheme.primary)),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : colorScheme.onSurface,
      ),
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      onSelected: (_) => setState(() => _selectedCategory = key),
    );
  }

  Widget _buildSliverHeader(String title, int count, IconData icon, Color accentColor, {Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Icon(icon, size: 17, color: accentColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: accentColor),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSliverProductList(List<InventoryItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          final qty = _selectedQuantities[item.id] ?? 0;
          return _buildProductRow(item, qty);
        }, childCount: items.length),
      ),
    );
  }

  Widget _buildProductRow(InventoryItem item, int qty) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = qty > 0;
    final isBestSeller = ProductTag.isBestSeller(item.tag);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4), width: isSelected ? 1.5 : 1),
      ),
      color: isSelected ? colorScheme.primary.withValues(alpha: 0.04) : colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (!isSelected) {
            HapticFeedback.lightImpact();
            final initialQty = item.isPreOrderRecommended ? item.recommendedPreOrderOrderQuantity : 1;
            _updateQuantity(item.id, initialQty);
          } else {
            _promptDirectQuantityDialog(item);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(imageUrl: item.imageUrl, size: 48, borderRadius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.hasPreOrderShortage) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'Shortage: ${item.preOrderShortage} (Pre-order: ${item.preOrderQuantity} > Stock: ${item.stockQuantity})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ] else if (item.isPreOrderRecommended) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '⚠️ Low Stock Alert (Pre-order: ${item.preOrderQuantity}, Stock: ${item.stockQuantity} leaves ${item.remainingStockAfterPreOrder} ≤ ${item.lowStockThreshold})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ] else if (item.preOrderQuantity > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          'Pre-order: ${item.preOrderQuantity}',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (isBestSeller) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                        child: const Text(
                          'Best Seller',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Cost: ${_currencyFormat.format(item.buyingPrice)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorScheme.primary),
                        ),
                        Text('•', style: TextStyle(color: colorScheme.outline)),
                        Text(
                          'Stock: ${item.stockQuantity}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: item.stockQuantity <= 0
                                ? colorScheme.error
                                : (item.isLowStock ? Colors.orange.shade800 : colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Stepper or Add button
              if (qty <= 0)
                FilledButton.tonal(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final initialQty = item.isPreOrderRecommended ? item.recommendedPreOrderOrderQuantity : 1;
                    _updateQuantity(item.id, initialQty);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(60, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _updateQuantity(item.id, qty - 1);
                          },
                          child: SizedBox(
                            width: 32,
                            height: 36,
                            child: Icon(
                              qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                              size: 17,
                              color: qty == 1 ? colorScheme.error : colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => _promptDirectQuantityDialog(item),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 32),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            child: Text(
                              '$qty',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _updateQuantity(item.id, qty + 1);
                          },
                          child: SizedBox(width: 32, height: 36, child: Icon(Icons.add_rounded, size: 17, color: colorScheme.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyBottomBar({
    required BuildContext context,
    required int totalSkus,
    required int totalUnits,
    required double totalCost,
    required List<InventoryItem> allInventory,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalSkus items • $totalUnits units',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  _currencyFormat.format(totalCost),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _onSubmit(allInventory),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(widget.isDirectCreationFlow ? Icons.receipt_long_rounded : Icons.check_rounded, size: 20),
            label: Text(
              widget.isDirectCreationFlow
                  ? (totalUnits > 0 ? 'Create Order ($totalUnits)' : 'Create Order')
                  : 'Apply to P.O. ($totalUnits)',
            ),
          ),
        ],
      ),
    );
  }
}
