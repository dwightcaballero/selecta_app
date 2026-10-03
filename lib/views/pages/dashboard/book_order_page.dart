import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/book_order/sticky_order_summary_bar.dart';
import 'package:selecta_ops/views/widgets/book_order/store_date_modal.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

/// Book Order Page where users select a Hapi Store and choose products.
/// Selecta products are categorized as Best Sellers, By Case, and By Piece, followed by Other Products at the very bottom.
///
/// When saved:
/// 1. Marks the unified order-delivery transaction as `Pending Picklist`.
/// 2. Temporarily deducts/reserves floating inventory (`reservedQuantity`) so items
///    cannot be overbooked while waiting for picklist completion.
/// 3. Returns to the previous screen / Dashboard.
class BookOrderPage extends StatefulWidget {
  const BookOrderPage({
    super.key,
    this.deliveryID = '',
    this.existingDelivery,
    this.initialStoreName = '',
    this.initialDate,
    this.returnUpdatedDeliveryOnSave = false,
  });

  final String deliveryID;
  final Delivery? existingDelivery;
  final String initialStoreName;
  final DateTime? initialDate;

  /// When true (e.g. opened from [PicklistPage] via "Add / Edit Products"),
  /// pops with the updated [Delivery] instead of pushing a new [PicklistPage].
  final bool returnUpdatedDeliveryOnSave;

  @override
  State<BookOrderPage> createState() => _BookOrderPageState();
}

class _BookOrderPageState extends State<BookOrderPage> {
  final DeliveryController _deliveryController = DeliveryController();
  final InventoryController _inventoryController = InventoryController();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final TextEditingController _storeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _remarksController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _hasUserManuallyPickedDate = false;
  String _searchQuery = '';
  bool _showSelectedOnly = false;
  bool _isSaving = false;
  Set<String> _placedProductNames = {};

  /// Keyed by `${source}:${productId}` -> selected quantity
  final Map<String, int> _selectedQuantities = {};

  /// Snapshot of quantities already reserved by this order (when editing an existing order)
  final Map<String, int> _initialOrderQuantities = {};

  /// Preserves `isPicked` state for items when editing from PicklistPage
  final Map<String, bool> _existingPickedFlags = {};

  bool get _isEditing => widget.deliveryID.isNotEmpty && widget.existingDelivery != null;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();

    if (_isEditing) {
      final d = widget.existingDelivery!;
      _storeController.text = d.storeName;
      _remarksController.text = d.remarks;
      if (d.deliveryDate != null) {
        _selectedDate = d.deliveryDate!.toDate();
      }
      for (final item in d.items) {
        final key = '${item.productSource}:${item.productId}';
        _selectedQuantities[key] = item.pickedQuantity;
        _initialOrderQuantities[key] = item.pickedQuantity;
        _existingPickedFlags[key] = item.isPicked;
      }
    } else {
      if (widget.initialStoreName.isNotEmpty) {
        _storeController.text = widget.initialStoreName;
      }
      if (widget.initialDate == null) {
        _initDefaultDeliveryDateByRole();
      }
    }

    if (_storeController.text.isNotEmpty) {
      _loadPlacedProductsForStore(_storeController.text, _selectedDate);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _storeController.text.trim().isNotEmpty) return;
        if (widget.initialDate == null && !_hasUserManuallyPickedDate) {
          await _initDefaultDeliveryDateByRole();
        }
        if (mounted && _storeController.text.trim().isEmpty) {
          _showStoreAndDateModal();
        }
      });
    }
  }

  Future<void> _loadPlacedProductsForStore(String storeName, DateTime date) async {
    if (storeName.trim().isEmpty) {
      if (mounted && _placedProductNames.isNotEmpty) {
        setState(() {
          _placedProductNames = {};
        });
      }
      return;
    }
    try {
      final placement = await PlacementService().getPlacementByStoreAndDate(storeName.trim(), date);
      if (!mounted) return;
      setState(() {
        if (placement != null) {
          _placedProductNames = placement.placedProductNames.map((n) => n.trim().toLowerCase()).toSet();
        } else {
          _placedProductNames = {};
        }
      });
    } catch (_) {}
  }

  Future<void> _initDefaultDeliveryDateByRole() async {
    final isDealer = await KVariables.getIsDealer();
    if (!mounted || _hasUserManuallyPickedDate || _isEditing) return;
    final now = DateTime.now();
    final defaultDate = isDealer ? now : now.add(const Duration(days: 1));
    setState(() {
      _selectedDate = defaultDate;
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _storeController.dispose();
    _searchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _itemKey(InventoryItem item) => '${item.source.key}:${item.id}';

  int _getSelectedQty(InventoryItem item) => _selectedQuantities[_itemKey(item)] ?? 0;

  /// Effective available stock for this item, including any units already reserved by this order.
  int _getMaxOrderableQty(InventoryItem item) {
    final alreadyInThisOrder = _initialOrderQuantities[_itemKey(item)] ?? 0;
    return item.availableQuantity + alreadyInThisOrder;
  }

  void _setSelectedQty(InventoryItem item, int newQty) {
    final key = _itemKey(item);
    final maxAllowed = _getMaxOrderableQty(item);
    final clamped = newQty.clamp(0, maxAllowed);

    if (newQty > maxAllowed && maxAllowed >= 0) {
      final incomingInfo = item.incomingQuantity > 0 ? ' (including ${item.incomingQuantity} incoming via PO)' : '';
      final reservedInfo = item.reservedQuantity > 0 ? ' (${item.reservedQuantity} reserved in pending picklists)' : '';
      ShowMessage.error(
        context,
        'Only $maxAllowed available for "${item.productName}"$incomingInfo$reservedInfo.',
      );
    }

    setState(() {
      if (clamped <= 0) {
        _selectedQuantities.remove(key);
      } else {
        _selectedQuantities[key] = clamped;
      }
    });
  }

  String _formatAppBarDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);
    final shortDate = DateFormat('MMM d').format(date);

    if (target == today) {
      return 'Today, $shortDate';
    } else if (target == tomorrow) {
      return 'Tomorrow, $shortDate';
    }
    return DateFormat('MMM d, y').format(date);
  }

  List<OrderItem> _buildOrderItemsList(List<InventoryItem> allInventory) {
    final Map<String, InventoryItem> byKey = {for (final item in allInventory) _itemKey(item): item};

    final List<OrderItem> result = [];
    for (final entry in _selectedQuantities.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;
      final invItem = byKey[entry.key];
      if (invItem != null) {
        result.add(
          OrderItem(
            productId: invItem.id,
            productName: invItem.productName,
            imageUrl: invItem.imageUrl,
            productSource: invItem.source.key,
            category: invItem.category,
            tag: invItem.tag,
            buyingPrice: invItem.buyingPrice,
            sellingPrice: invItem.sellingPrice,
            orderedQuantity: qty,
            pickedQuantity: qty,
            isPicked: _existingPickedFlags[entry.key] ?? false,
          ),
        );
      } else if (_isEditing) {
        // Fallback if item was previously on the order
        final existing = widget.existingDelivery!.items.where((i) => '${i.productSource}:${i.productId}' == entry.key);
        if (existing.isNotEmpty) {
          final first = existing.first;
          result.add(first.copyWith(orderedQuantity: qty, pickedQuantity: qty));
        }
      }
    }
    result.sort((a, b) {
      return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
    });
    return result;
  }

  Future<void> _promptQuantityDialog(InventoryItem item) async {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    final currentQty = _getSelectedQty(item);
    final maxAllowed = _getMaxOrderableQty(item);
    final defaultQty = currentQty > 0 ? currentQty : (maxAllowed >= 1 ? 1 : 0);
    final initialText = defaultQty > 0 ? defaultQty.toString() : '';
    final controller = TextEditingController(text: initialText)..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

    final int? entered = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final currentTyped = int.tryParse(controller.text.trim()) ?? 0;

            void applyPreset(int targetQty) {
              final clamped = targetQty.clamp(0, maxAllowed);
              final text = clamped > 0 ? '$clamped' : '';
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              setDialogState(() {});
            }

            final liveTotal = currentTyped * item.sellingPrice;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Theme.of(ctx).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Header: Image + Product Info + Close ────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CachedProductImage(imageUrl: item.imageUrl, size: 46, borderRadius: 10),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.2),
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      _currencyFormat.format(item.sellingPrice),
                                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colorScheme.primary),
                                    ),
                                    Text('•', style: TextStyle(color: colorScheme.outline)),
                                    Text(
                                      '$maxAllowed available',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),

                      if (item.incomingQuantity > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF0284C7)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '${item.incomingQuantity} incoming via Purchase Order (${item.stockQuantity} physical on hand)',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (item.reservedQuantity > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFD97706).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFD97706)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '${item.reservedQuantity} reserved in pending picklists (${item.stockQuantity} on hand)',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // ── Stepper Card ───────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            // Minus Button
                            Material(
                              color: currentTyped > 0 ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: currentTyped > 0 ? () => applyPreset(currentTyped - 1) : null,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.remove_rounded,
                                    size: 24,
                                    color: currentTyped > 0 ? colorScheme.primary : colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),

                            // Number Input / Display
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: controller,
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: currentTyped > 0 ? colorScheme.primary : colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: '0',
                                      hintStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colorScheme.outlineVariant),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (val) {
                                      Navigator.pop(ctx, int.tryParse(val.trim()) ?? 0);
                                    },
                                  ),
                                  Text(
                                    'units (max $maxAllowed)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),

                            // Plus Button
                            Material(
                              color: (currentTyped < maxAllowed && maxAllowed > 0) ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: (currentTyped < maxAllowed && maxAllowed > 0) ? () => applyPreset(currentTyped + 1) : null,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 24,
                                    color: (currentTyped < maxAllowed && maxAllowed > 0) ? colorScheme.primary : colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Live Subtotal Banner ───────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Item Total',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              _currencyFormat.format(liveTotal),
                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: colorScheme.primary),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Action Buttons ────────────────────────────────────
                      Row(
                        children: [
                          if (currentQty > 0) ...[
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx, 0),
                              icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
                              label: Text(
                                'Remove',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colorScheme.error),
                              ),
                            ),
                            const Spacer(),
                          ] else ...[
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Cancel',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const Spacer(),
                          ],
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? 0);
                            },
                            child: const Text('Apply', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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

    if (!mounted) return;
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (entered != null) {
      _setSelectedQty(item, entered);
    }
  }

  Future<void> _showCartSummarySheet(List<InventoryItem> allInventory) async {
    final items = _buildOrderItemsList(allInventory);
    if (items.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final totalAmount = _deliveryController.computeItemsOrderAmount(items);
        final totalUnits = items.fold<int>(0, (sum, i) => sum + i.pickedQuantity);

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.shopping_bag_outlined, color: colorScheme.primary, size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Order Summary (${items.length} SKU${items.length == 1 ? '' : 's'} • $totalUnits units)',
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _selectedQuantities.clear());
                          Navigator.pop(ctx);
                        },
                        icon: Icon(Icons.delete_sweep_outlined, size: 22, color: colorScheme.error),
                        label: Text('Clear', style: TextStyle(fontSize: 13.5, color: colorScheme.error)),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelecta = item.productSource == 'selecta';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CachedProductImage(imageUrl: item.imageUrl, size: 52),
                          title: Text(item.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${isSelecta ? 'Selecta' : 'Other'} • ${_currencyFormat.format(item.sellingPrice)} × ${item.pickedQuantity}',
                            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                          ),
                          trailing: Text(
                            _currencyFormat.format(item.lineTotal),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Order Amount', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                      Text(
                        _currencyFormat.format(totalAmount),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onSaveOrder(List<InventoryItem> allInventory) async {
    if (_isSaving) return;
    if (_storeController.text.trim().isEmpty) {
      ShowMessage.error(context, 'Please select a Hapi Store first.');
      _showStoreAndDateModal();
      return;
    }

    final orderItems = _buildOrderItemsList(allInventory);
    if (orderItems.isEmpty) {
      ShowMessage.error(context, 'Please select at least 1 product to book an order.');
      return;
    }

    final storeName = _storeController.text.trim();
    final totalAmount = _deliveryController.computeItemsOrderAmount(orderItems);
    final totalUnits = orderItems.fold<int>(0, (sum, i) => sum + i.pickedQuantity);

    final confirmed = await ShowMessage.confirm(
      context,
      title: _isEditing ? 'Update Order' : 'Save Order',
      message: _isEditing
          ? 'Save changes to $storeName order (${orderItems.length} items, $totalUnits units • ${_currencyFormat.format(totalAmount)})?'
          : 'Save order for $storeName (${orderItems.length} items, $totalUnits units • ${_currencyFormat.format(totalAmount)})?\n\n'
                'This will mark the order as Pending Picklist and reserve floating inventory.',
      icon: Icons.check_circle_outline,
      confirmText: 'Save Order',
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final isOnline = await OfflineSyncService.isOnline();
      if (!isOnline) {
        if (_isEditing) {
          await OfflineSyncService.instance.enqueueOrderUpdate(
            deliveryId: widget.deliveryID,
            storeName: storeName,
            selectedDate: _selectedDate,
            items: orderItems,
            remarks: _remarksController.text,
          );
        } else {
          await OfflineSyncService.instance.enqueueOrderCreation(
            storeName: storeName,
            selectedDate: _selectedDate,
            items: orderItems,
            remarks: _remarksController.text,
          );
        }
        if (!mounted) return;
        ShowMessage.warning(
          context,
          'Saved to Offline Queue! Order will automatically sync once connectivity is restored.',
        );
        Navigator.pop(context);
        return;
      }

      if (_isEditing) {
        final updated = await _deliveryController.updateBookedOrder(
          deliveryId: widget.deliveryID,
          currentDelivery: widget.existingDelivery!,
          storeName: storeName,
          selectedDate: _selectedDate,
          items: orderItems,
          remarks: _remarksController.text,
        ).timeout(const Duration(seconds: 5));
        if (!mounted) return;
        ShowMessage.success(context, 'Order updated for $storeName!');
        Navigator.pop(context, updated);
      } else {
        final createdResult = await _deliveryController.createBookedOrder(
          storeName: storeName,
          selectedDate: _selectedDate,
          items: orderItems,
          remarks: _remarksController.text,
        ).timeout(const Duration(seconds: 5));
        if (!mounted) return;
        ShowMessage.success(context, 'Order saved for $storeName! Marked as Pending Picklist.');
        Navigator.pop(context, createdResult.delivery);
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      final isOfflineOrTimeout = e is TimeoutException ||
          errStr.contains('timeout') ||
          errStr.contains('network') ||
          errStr.contains('socket') ||
          errStr.contains('unavailable') ||
          errStr.contains('client is offline');

      if (isOfflineOrTimeout) {
        try {
          if (_isEditing) {
            await OfflineSyncService.instance.enqueueOrderUpdate(
              deliveryId: widget.deliveryID,
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
            );
          } else {
            await OfflineSyncService.instance.enqueueOrderCreation(
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
            );
          }
          if (!mounted) return;
          ShowMessage.warning(
            context,
            'Saved to Offline Queue! Order will automatically sync once connectivity is restored.',
          );
          Navigator.pop(context);
          return;
        } catch (_) {
          // If local enqueuing also fails, fall through to error message
        }
      }

      if (mounted) {
        ShowMessage.error(context, 'Failed to save order: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedStoreName = _storeController.text.trim();
    final hasSelectedStore = selectedStoreName.isNotEmpty;

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryController.getActiveInventoryStream(),
      builder: (context, snapshot) {
        final allInventory = (snapshot.data ?? []).where((item) => item.isActive).toList();

        final orderItems = _buildOrderItemsList(allInventory);
        final totalAmount = _deliveryController.computeItemsOrderAmount(orderItems);
        final totalUnits = orderItems.fold<int>(0, (sum, i) => sum + i.pickedQuantity);

        return Scaffold(
          appBar: CustomAppbar(
            title: _isEditing ? 'Edit Order' : 'Store Order',
            subtitle: hasSelectedStore ? '$selectedStoreName • ${_formatAppBarDate(_selectedDate)}' : 'Order for a Hapi Store',
            centerTitle: false,
            actions: [_buildToggleStoreDateAction()],
          ),
          bottomNavigationBar: hasSelectedStore
              ? _buildStickyOrderSummaryBar(
                  colorScheme: colorScheme,
                  allInventory: allInventory,
                  skuCount: orderItems.length,
                  totalUnits: totalUnits,
                  totalAmount: totalAmount,
                )
              : null,
          body: Column(
            children: [
              if (!hasSelectedStore)
                Expanded(child: _buildSelectStorePrompt(colorScheme))
              else ...[
                // ── Search & Selected Filter Bar ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: false,
                            onTapOutside: (_) => _searchFocusNode.unfocus(),
                            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: 'Search products...',
                              hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                              prefixIcon: Icon(Icons.search, size: 22, color: colorScheme.primary),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 22),
                                      onPressed: () {
                                        _searchController.clear();
                                        _searchFocusNode.unfocus();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: colorScheme.outlineVariant),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _showSelectedOnly,
                        label: Text(
                          'Selected (${orderItems.length})',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: _showSelectedOnly ? colorScheme.onPrimary : colorScheme.onSurface,
                          ),
                        ),
                        selectedColor: colorScheme.primary,
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onSelected: (val) => setState(() => _showSelectedOnly = val),
                      ),
                    ],
                  ),
                ),

                // ── Unified Product List (Selecta first, Other Products at bottom) ──
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : _buildUnifiedProductList(allInventory: allInventory, colorScheme: colorScheme),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleStoreDateAction() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
      ),
      child: IconButton(
        icon: const Icon(Icons.storefront_outlined, size: 20, color: Colors.white),
        onPressed: _showStoreAndDateModal,
        tooltip: 'Store & Delivery Date',
        splashRadius: 20,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _showStoreAndDateModal() async {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await StoreDateModal.show(
      context: context,
      initialStoreName: _storeController.text,
      initialDate: _selectedDate,
      initialRemarks: _remarksController.text,
    );

    if (result != null && mounted) {
      final newStore = result.storeName;
      final storeChanged = _storeController.text.trim() != newStore;
      final dateChanged = _selectedDate != result.selectedDate;
      setState(() {
        _storeController.text = newStore;
        _selectedDate = result.selectedDate;
        _remarksController.text = result.remarks;
        _hasUserManuallyPickedDate = true;
      });
      if (storeChanged || dateChanged) {
        _loadPlacedProductsForStore(_storeController.text, _selectedDate);
      }
    }
  }

  Widget _buildSelectStorePrompt(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.storefront_outlined, size: 52, color: colorScheme.primary),
            ),
            const SizedBox(height: 18),
            const Text('Select a Store & Delivery Date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Choose a Hapi Store and delivery date to view available products and start booking an order.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showStoreAndDateModal,
              icon: const Icon(Icons.storefront_outlined, size: 20),
              label: const Text('Choose Store & Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required Color accentColor,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
  }

  Widget _buildUnifiedProductList({required List<InventoryItem> allInventory, required ColorScheme colorScheme}) {
    if (allInventory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 52, color: colorScheme.outline),
              const SizedBox(height: 14),
              const Text('No Active Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Activate products in the catalog to book orders.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = allInventory.where((item) {
      if (!item.isActive) return false;
      if (_showSelectedOnly && _getSelectedQty(item) <= 0) return false;
      if (_searchQuery.isNotEmpty && !item.productName.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                _showSelectedOnly ? 'No selected products found' : 'No products matching "$_searchQuery"',
                style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final selectaFiltered = filtered.where((i) => i.source == InventoryProductSource.selecta).toList();
    final otherFiltered = filtered.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(_compareProducts);

    final bestSellerProducts = selectaFiltered.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSellerSelecta = selectaFiltered.where((i) => !ProductTag.isBestSeller(i.tag)).toList();

    final caseProducts = nonBestSellerSelecta.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = nonBestSellerSelecta.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

    final entries = <_BookOrderListEntry>[];

    // 1. Best Sellers at the top
    if (bestSellerProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(title: 'Best Sellers', count: bestSellerProducts.length, icon: Icons.star_rounded, accentColor: const Color(0xFFD97706)),
      );
      for (final p in bestSellerProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 2. Selecta: By Case
    if (caseProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(title: 'By Case', count: caseProducts.length, icon: Icons.all_inbox_rounded, accentColor: const Color(0xFFEA580C)),
      );
      for (final p in caseProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 3. Selecta: By Piece
    if (pieceProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(title: 'By Piece', count: pieceProducts.length, icon: Icons.icecream_outlined, accentColor: colorScheme.primary),
      );
      for (final p in pieceProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 5. Other Products at the very bottom
    if (otherFiltered.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(
          title: 'Other Products',
          count: otherFiltered.length,
          icon: Icons.inventory_2_outlined,
          accentColor: const Color(0xFF475569),
        ),
      );
      for (final p in otherFiltered) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _BookOrderHeaderEntry) {
          return _buildCategorySectionHeader(
            title: entry.title,
            count: entry.count,
            icon: entry.icon,
            accentColor: entry.accentColor,
            colorScheme: colorScheme,
          );
        } else if (entry is _BookOrderCardEntry) {
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildProductOrderCard(entry.item, colorScheme));
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildProductOrderCard(InventoryItem item, ColorScheme colorScheme) {
    return ProductOrderCard(
      item: item,
      selectedQty: _getSelectedQty(item),
      maxOrderable: _getMaxOrderableQty(item),
      isPlaced: _placedProductNames.contains(item.productName.trim().toLowerCase()),
      currencyFormat: _currencyFormat,
      onTap: () => _promptQuantityDialog(item),
    );
  }

  Widget _buildStickyOrderSummaryBar({
    required ColorScheme colorScheme,
    required List<InventoryItem> allInventory,
    required int skuCount,
    required int totalUnits,
    required double totalAmount,
  }) {
    return StickyOrderSummaryBar(
      skuCount: skuCount,
      totalUnits: totalUnits,
      totalAmount: totalAmount,
      currencyFormat: _currencyFormat,
      isSaving: _isSaving,
      onTapCartSummary: () => _showCartSummarySheet(allInventory),
      onSaveOrder: () => _onSaveOrder(allInventory),
    );
  }
}

sealed class _BookOrderListEntry {}

class _BookOrderHeaderEntry extends _BookOrderListEntry {
  final String title;
  final int count;
  final IconData icon;
  final Color accentColor;
  _BookOrderHeaderEntry({required this.title, required this.count, required this.icon, required this.accentColor});
}

class _BookOrderCardEntry extends _BookOrderListEntry {
  final InventoryItem item;
  _BookOrderCardEntry(this.item);
}
