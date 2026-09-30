import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/delivery_controller.dart';
import 'package:flutter_app/controllers/inventory_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/inventory_movement.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';
import 'package:intl/intl.dart';

/// Book Order Page where users select a Hapi Store and choose products.
/// Best Seller products are listed first at the top, followed by Selecta products (By Case, By Piece), and Other Products at the very bottom.
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
      ShowMessage.error(
        context,
        'Only $maxAllowed available in stock for "${item.productName}"'
        '${item.reservedQuantity > 0 ? ' (${item.reservedQuantity} reserved in pending picklists)' : ''}.',
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

  Future<void> _pickDeliveryDate() async {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (!mounted) return;
    _searchFocusNode.unfocus();
    if (picked != null) {
      setState(() {
        _hasUserManuallyPickedDate = true;
        _selectedDate = picked;
      });
      _loadPlacedProductsForStore(_storeController.text, picked);
    }
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
      return Helperfunctions.compareBySrpAndName(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
      );
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Theme.of(ctx).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Header: Image + Product Info + Close ────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CachedProductImage(imageUrl: item.imageUrl, size: 56, borderRadius: 12),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, height: 1.25)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _currencyFormat.format(item.sellingPrice),
                                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: colorScheme.primary),
                                    ),
                                    Text(' • ', style: TextStyle(color: colorScheme.outline)),
                                    Text(
                                      '$maxAllowed in stock',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 22),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),

                      if (item.reservedQuantity > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFFD97706).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${item.reservedQuantity} reserved in pending picklists (${item.stockQuantity} on hand)',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // ── Stepper Card ───────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            // Minus Button
                            Material(
                              color: currentTyped > 0 ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: currentTyped > 0 ? () => applyPreset(currentTyped - 1) : null,
                                child: SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: Icon(
                                    Icons.remove_rounded,
                                    size: 30,
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
                                      fontSize: 36,
                                      fontWeight: FontWeight.w900,
                                      color: currentTyped > 0 ? colorScheme.primary : colorScheme.onSurface,
                                      letterSpacing: -0.5,
                                    ),
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintText: '0',
                                      hintStyle: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: colorScheme.outlineVariant),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (val) {
                                      Navigator.pop(ctx, int.tryParse(val.trim()) ?? 0);
                                    },
                                  ),
                                  Text(
                                    'units (max $maxAllowed)',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),

                            // Plus Button
                            Material(
                              color: (currentTyped < maxAllowed && maxAllowed > 0) ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: (currentTyped < maxAllowed && maxAllowed > 0) ? () => applyPreset(currentTyped + 1) : null,
                                child: SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 30,
                                    color: (currentTyped < maxAllowed && maxAllowed > 0) ? colorScheme.primary : colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ── Live Subtotal Banner ───────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              _currencyFormat.format(liveTotal),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorScheme.primary),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ── Action Buttons ────────────────────────────────────
                      Row(
                        children: [
                          if (currentQty > 0) ...[
                            TextButton.icon(
                              onPressed: () => Navigator.pop(ctx, 0),
                              icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
                              label: Text(
                                'Remove',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorScheme.error),
                              ),
                            ),
                            const Spacer(),
                          ] else ...[
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Cancel',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const Spacer(),
                          ],
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? 0);
                            },
                            child: const Text('Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _selectedQuantities.clear());
                          Navigator.pop(ctx);
                        },
                        icon: Icon(Icons.delete_sweep_outlined, size: 22, color: colorScheme.error),
                        label: Text('Clear', style: TextStyle(fontSize: 15, color: colorScheme.error)),
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
                          title: Text(item.productName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${isSelecta ? 'Selecta' : 'Other'} • ${_currencyFormat.format(item.sellingPrice)} × ${item.pickedQuantity}',
                            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                          ),
                          trailing: Text(
                            _currencyFormat.format(item.lineTotal),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Order Amount', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(
                        _currencyFormat.format(totalAmount),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.primary),
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
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please select a Hapi Store first.');
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
      if (_isEditing) {
        final updated = await _deliveryController.updateBookedOrder(
          deliveryId: widget.deliveryID,
          currentDelivery: widget.existingDelivery!,
          storeName: storeName,
          selectedDate: _selectedDate,
          items: orderItems,
          remarks: _remarksController.text,
        );
        if (!mounted) return;
        ShowMessage.success(context, 'Order updated for $storeName!');
        Navigator.pop(context, updated);
      } else {
        final createdResult = await _deliveryController.createBookedOrder(
          storeName: storeName,
          selectedDate: _selectedDate,
          items: orderItems,
          remarks: _remarksController.text,
        );
        if (!mounted) return;
        ShowMessage.success(context, 'Order saved for $storeName! Marked as Pending Picklist.');
        Navigator.pop(context, createdResult.delivery);
      }
    } catch (e) {
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
        final allInventory = snapshot.data ?? [];

        final orderItems = _buildOrderItemsList(allInventory);
        final totalAmount = _deliveryController.computeItemsOrderAmount(orderItems);
        final totalUnits = orderItems.fold<int>(0, (sum, i) => sum + i.pickedQuantity);

        return Scaffold(
          appBar: CustomAppbar(title: _isEditing ? 'Edit Order' : 'Book Order', centerTitle: false, actions: [_buildAppBarDateAction()]),
          bottomNavigationBar: hasSelectedStore
              ? _buildStickyOrderSummaryBar(
                  colorScheme: colorScheme,
                  allInventory: allInventory,
                  skuCount: orderItems.length,
                  totalUnits: totalUnits,
                  totalAmount: totalAmount,
                )
              : null,
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                // ── Store Header Card (permanently visible at the top) ──
                _buildStoreHeader(colorScheme),

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
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'Search products...',
                                hintStyle: TextStyle(fontSize: 15.5, color: colorScheme.onSurfaceVariant),
                                prefixIcon: Icon(Icons.search, size: 24, color: colorScheme.primary),
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
          ),
        );
      },
    );
  }

  Widget _buildAppBarDateAction() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pickDeliveryDate,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                _formatAppBarDate(_selectedDate),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectStorePrompt(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.storefront_outlined, size: 48, color: colorScheme.primary),
            ),
            const SizedBox(height: 16),
            const Text('Select a Hapi Store First', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Choose a Hapi Store above to view available products.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: HapistorePickerField(
        controller: _storeController,
        label: 'Hapi Store *',
        validator: (val) => (val == null || val.trim().isEmpty) ? 'Please select a Hapi Store' : null,
        onChanged: () {
          setState(() {});
          _loadPlacedProductsForStore(_storeController.text, _selectedDate);
        },
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
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    return Helperfunctions.compareBySrpAndName(
      nameA: a.productName,
      priceA: a.sellingPrice,
      nameB: b.productName,
      priceB: b.sellingPrice,
    );
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
              const Text('No Active Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Activate products in the catalog to book orders.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = allInventory.where((item) {
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

    final bestSellerProducts = filtered.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSellerFiltered = filtered.where((i) => !ProductTag.isBestSeller(i.tag)).toList();

    final selectaFiltered = nonBestSellerFiltered.where((i) => i.source == InventoryProductSource.selecta).toList()..sort(_compareProducts);
    final otherFiltered = nonBestSellerFiltered.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(_compareProducts);

    final caseProducts = selectaFiltered.where((i) => i.category.trim().toLowerCase().contains('case')).toList();
    final pieceProducts = selectaFiltered.where((i) => !i.category.trim().toLowerCase().contains('case')).toList();

    final entries = <_BookOrderListEntry>[];

    // 1. Best Seller at the top
    if (bestSellerProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(
          title: 'Best Seller',
          count: bestSellerProducts.length,
          icon: Icons.star_rounded,
          accentColor: const Color(0xFFD97706),
        ),
      );
      for (final p in bestSellerProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 2. Selecta: By Case
    if (caseProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(
          title: 'By Case',
          count: caseProducts.length,
          icon: Icons.all_inbox_rounded,
          accentColor: const Color(0xFFEA580C),
        ),
      );
      for (final p in caseProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 3. Selecta: By Piece
    if (pieceProducts.isNotEmpty) {
      entries.add(
        _BookOrderHeaderEntry(
          title: 'By Piece',
          count: pieceProducts.length,
          icon: Icons.icecream_outlined,
          accentColor: colorScheme.primary,
        ),
      );
      for (final p in pieceProducts) {
        entries.add(_BookOrderCardEntry(p));
      }
    }

    // 4. Other Products at the very bottom
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
    final selectedQty = _getSelectedQty(item);
    final isSelected = selectedQty > 0;
    final maxOrderable = _getMaxOrderableQty(item);
    final isOutOfStock = maxOrderable <= 0;

    final bool isBestSeller = ProductTag.isBestSeller(item.tag);
    final bool isNewProduct = ProductTag.isNewProduct(item.tag);
    final bool isPlaced = _placedProductNames.contains(item.productName.trim().toLowerCase());
    final bool showNotPlacedMark = isBestSeller && !isPlaced;

    final Color stockColor = isOutOfStock
        ? colorScheme.error
        : (maxOrderable <= item.lowStockThreshold ? const Color(0xFFD97706) : colorScheme.primary);

    Color cardBgColor = colorScheme.surface;
    Color cardBorderColor = colorScheme.outlineVariant.withValues(alpha: 0.45);
    double cardBorderWidth = 1.0;

    if (isSelected) {
      cardBgColor = colorScheme.primary.withValues(alpha: 0.05);
      cardBorderColor = colorScheme.primary;
      cardBorderWidth = 1.5;
    } else if (isBestSeller) {
      cardBgColor = const Color(0xFFFFFBEB).withValues(alpha: 0.5);
      cardBorderColor = const Color(0xFFFDE68A);
      cardBorderWidth = 1.2;
    } else if (isNewProduct) {
      cardBgColor = const Color(0xFFF0F9FF).withValues(alpha: 0.5);
      cardBorderColor = const Color(0xFFBAE6FD);
      cardBorderWidth = 1.2;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor, width: cardBorderWidth),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isOutOfStock ? null : () => _promptQuantityDialog(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CachedProductImage(imageUrl: item.imageUrl, isActive: !isOutOfStock, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBestSeller || isNewProduct || showNotPlacedMark) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (isBestSeller)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded, size: 13, color: Color(0xFFD97706)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Best Seller',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                  ),
                                ],
                              ),
                            ),
                          if (isNewProduct)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fiber_new_rounded, size: 14, color: Color(0xFF0284C7)),
                                  SizedBox(width: 3),
                                  Text(
                                    'New Product',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                  ),
                                ],
                              ),
                            ),
                          if (showNotPlacedMark)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFDC2626)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Not Placed',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      item.productName,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: isOutOfStock ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7,
                      runSpacing: 2,
                      children: [
                        Text(
                          _currencyFormat.format(item.sellingPrice),
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: colorScheme.primary),
                        ),
                        Text(
                          isOutOfStock ? 'Out of stock' : '',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: stockColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Icon-only Add button (plus icon) when qty = 0
              if (!isSelected)
                SizedBox(
                  width: 46,
                  height: 46,
                  child: FilledButton(
                    onPressed: isOutOfStock ? null : () => _promptQuantityDialog(item),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      minimumSize: const Size(46, 46),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Icon(Icons.add_rounded, size: 24),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _promptQuantityDialog(item),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(23)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          '$selectedQty',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
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

  Widget _buildStickyOrderSummaryBar({
    required ColorScheme colorScheme,
    required List<InventoryItem> allInventory,
    required int skuCount,
    required int totalUnits,
    required double totalAmount,
  }) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: skuCount > 0 ? () => _showCartSummarySheet(allInventory) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$skuCount SKU${skuCount == 1 ? '' : 's'} • $totalUnits unit${totalUnits == 1 ? '' : 's'}',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                              ),
                              if (skuCount > 0) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: colorScheme.primary),
                              ],
                            ],
                          ),
                          Text(
                            _currencyFormat.format(totalAmount),
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSaving ? null : () => _onSaveOrder(allInventory),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(148, 50),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: const Text('Save Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
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
