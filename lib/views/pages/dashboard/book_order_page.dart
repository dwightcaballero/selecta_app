import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/book_order/receipt_scan_flow.dart';
import 'package:selecta_ops/views/widgets/book_order/sticky_order_summary_bar.dart';
import 'package:selecta_ops/views/widgets/book_order/store_date_modal.dart';
import 'package:selecta_ops/views/widgets/book_order/store_recommendations_modal.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/models/promo.dart';
import 'package:selecta_ops/services/promo_service.dart';
import 'package:selecta_ops/views/widgets/book_order/promo_cards_section.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/responsive.dart';

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
  String _selectedCategoryFilter = 'all';
  bool _hideOutOfStock = false;
  bool _isSaving = false;
  bool _isScanning = false;
  Set<String> _placedProductNames = {};

  /// Keyed by `${source}:${productId}` -> selected quantity
  final Map<String, int> _selectedQuantities = {};

  /// Preserves receipt top-to-bottom sequence of item keys from the most recent scan
  final List<String> _scannedReceiptOrder = [];

  /// Preserves the raw text printed on the receipt for each item key
  final Map<String, String> _scannedRawTexts = {};

  /// Tracks item keys corrected by the user during/after scanning
  final Set<String> _correctedReceiptKeys = {};

  /// When true (default after scanning), orders selected items according to the scanned receipt
  bool _sortByReceiptOrder = true;

  /// Snapshot of quantities already reserved by this order (when editing an existing order)
  final Map<String, int> _initialOrderQuantities = {};

  /// Preserves `isPicked` state for items when editing from PicklistPage
  final Map<String, bool> _existingPickedFlags = {};

  /// Latest inventory list retrieved from active stream
  List<InventoryItem> _latestInventory = const [];

  /// Active promotions from Firestore
  List<Promo> _activePromos = const [];

  /// Number of times promotions have been availed by the selected store
  Map<String, int> _storePromoUsage = const {};

  StreamSubscription<List<Promo>>? _promosSub;

  bool get _isEditing => widget.deliveryID.isNotEmpty && widget.existingDelivery != null;

  bool get _isFutureDeliveryDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return target.isAfter(today);
  }

  bool get _hasUnsavedChanges {
    if (_isEditing) {
      if (_remarksController.text.trim() != (widget.existingDelivery?.remarks ?? '')) return true;
      if (_storeController.text.trim() != (widget.existingDelivery?.storeName ?? '')) return true;
      if (_selectedQuantities.length != _initialOrderQuantities.length) return true;
      for (final entry in _selectedQuantities.entries) {
        if (entry.value != (_initialOrderQuantities[entry.key] ?? 0)) return true;
      }
      return false;
    }
    final hasItems = _selectedQuantities.values.any((qty) => qty > 0);
    final hasStore = _storeController.text.trim().isNotEmpty && _storeController.text.trim() != widget.initialStoreName;
    final hasRemarks = _remarksController.text.trim().isNotEmpty;
    return hasItems || hasStore || hasRemarks;
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();

    _promosSub = _deliveryController.promoService.streamActivePromos().listen((promos) {
      if (mounted) {
        setState(() => _activePromos = promos);
      }
    });

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
    _loadStorePromoUsage(storeName);
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
      final placed = <String>{};
      if (placement != null) {
        for (final n in placement.placedProductNames) {
          placed.add(n.trim().toLowerCase());
        }
        final legacyNames = [
          "Mag Vanilla",
          "Mag Almond",
          "Cornetto Choc",
          "Cornetto Vanilla",
          "Paddle Pop Choc",
          "Paddle Pop Straw",
          "Solero Split",
          "Calippo",
          "Sup Double Dutch",
          "Sup Queso Real",
          "Sup Rocky Road",
          "Sup Cookies & Cream",
        ];
        final flags = [
          placement.cotc1,
          placement.cotc2,
          placement.cotc3,
          placement.cotc4,
          placement.cotc5,
          placement.cotc6,
          placement.cotc7,
          placement.cotc8,
          placement.cotc9,
          placement.cotc10,
          placement.cotc11,
          placement.cotc12,
        ];
        for (int i = 0; i < legacyNames.length && i < flags.length; i++) {
          if (flags[i]) {
            placed.add(legacyNames[i].trim().toLowerCase());
          }
        }
      }

      // Expand with active placement pairs (if either product in a pair is placed, both are considered placed)
      try {
        final config = await ConfigurationService().getConfiguration();
        for (final pair in config.placementPairs) {
          final p1 = pair.product1.trim().toLowerCase();
          final p2 = pair.product2.trim().toLowerCase();
          final hasP1 = placed.contains(p1);
          final hasP2 = placed.contains(p2);
          if (hasP1 || hasP2) {
            placed.add(p1);
            placed.add(p2);
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _placedProductNames = placed;
      });
    } catch (_) {}
  }

  Future<void> _loadStorePromoUsage(String storeName) async {
    if (storeName.trim().isEmpty) {
      if (mounted && _storePromoUsage.isNotEmpty) {
        setState(() => _storePromoUsage = const {});
      }
      return;
    }
    try {
      final usage = await _deliveryController.promoService.getStorePromoUsage(
        storeName.trim(),
        excludeDeliveryId: widget.deliveryID.isNotEmpty ? widget.deliveryID : null,
      );
      if (mounted) {
        setState(() => _storePromoUsage = usage);
      }
    } catch (_) {}
  }

  /// Single point of evaluation for promotional rules, discounts, and free item injection.
  PromoEvaluationResult _evaluatePromos(List<OrderItem> rawItems, List<InventoryItem> allInventory) {
    final storeName = _storeController.text.trim();
    if (storeName.isEmpty || rawItems.isEmpty || _activePromos.isEmpty) {
      final gross = rawItems.fold<double>(0.0, (acc, i) => acc + i.lineTotal);
      return PromoEvaluationResult(
        appliedPromos: const [],
        grossAmount: gross,
        discountAmount: 0.0,
        netAmount: gross,
      );
    }
    return _deliveryController.promoService.evaluate(
      items: rawItems,
      storeName: storeName,
      date: _selectedDate,
      activePromos: _activePromos,
      usedCounts: _storePromoUsage,
      availableStock: {for (final i in allInventory) i.id: _getMaxOrderableQty(i)},
      productBuyingPrices: {for (final i in allInventory) i.id: i.buyingPrice},
    );
  }

  /// Adds all required items for a promotional bundle directly to the cart.
  void _addPromoBundleToCart(Promo promo, List<InventoryItem> allInventory) {
    final Map<String, InventoryItem> invMap = {for (final item in allInventory) item.id: item};

    // Pre-check stock
    for (final rule in promo.rules) {
      final inv = invMap[rule.productId];
      if (inv == null) {
        ShowMessage.error(context, 'Promo item "${rule.productName}" is not available in inventory.');
        return;
      }
      final current = _getSelectedQty(inv);
      final maxAllowed = _getMaxOrderableQty(inv);
      if (current + rule.requiredQty > maxAllowed) {
        ShowMessage.error(context, 'Cannot add "${promo.name}": Insufficient stock for "${rule.productName}".');
        return;
      }
    }

    // Apply bundle quantities
    setState(() {
      for (final rule in promo.rules) {
        final inv = invMap[rule.productId];
        if (inv != null) {
          final current = _getSelectedQty(inv);
          _setSelectedQty(inv, current + rule.requiredQty);
        }
      }
    });

    HapticFeedback.mediumImpact();
    ShowMessage.success(context, 'Added "${promo.name}" bundle to cart!');
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
    _promosSub?.cancel();
    _searchFocusNode.dispose();
    _storeController.dispose();
    _searchController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _itemKey(InventoryItem item) => '${item.source.key}:${item.id}';

  int _getSelectedQty(InventoryItem item) => _selectedQuantities[_itemKey(item)] ?? 0;

  /// Effective available stock for this item, including any units already reserved by this order.
  /// Regardless of delivery date, the user can only add quantity based on available stock.
  int _getMaxOrderableQty(InventoryItem item) {
    final alreadyInThisOrder = _initialOrderQuantities[_itemKey(item)] ?? 0;
    return (item.availableQuantity + alreadyInThisOrder).clamp(0, 999999);
  }

  void _setSelectedQty(InventoryItem item, int newQty) {
    final key = _itemKey(item);
    final maxAllowed = _getMaxOrderableQty(item);
    final clamped = newQty.clamp(0, maxAllowed);

    if (newQty > maxAllowed && maxAllowed >= 0) {
      final incomingInfo = item.incomingQuantity > 0 ? ' (including ${item.incomingQuantity} incoming via PO)' : '';
      final reservedInfo = item.reservedQuantity > 0 ? ' (${item.reservedQuantity} reserved in pending picklists)' : '';
      ShowMessage.error(context, 'Only $maxAllowed available for "${item.productName}"$incomingInfo$reservedInfo.');
    }

    setState(() {
      if (clamped <= 0) {
        _selectedQuantities.remove(key);
      } else {
        _selectedQuantities[key] = clamped;
      }
    });
  }

  /// Clamps any selected quantities that exceed available stock.
  void _clampQuantitiesToAvailableStock(List<InventoryItem> inventory) {
    if (_selectedQuantities.isEmpty || inventory.isEmpty) return;
    final Map<String, InventoryItem> invMap = {for (final item in inventory) _itemKey(item): item};

    bool clampedAny = false;
    final List<String> toRemove = [];

    _selectedQuantities.forEach((key, qty) {
      final item = invMap[key];
      if (item != null) {
        final alreadyInOrder = _initialOrderQuantities[key] ?? 0;
        final maxAllowed = (item.availableQuantity + alreadyInOrder).clamp(0, 999999);
        if (qty > maxAllowed) {
          clampedAny = true;
          if (maxAllowed <= 0) {
            toRemove.add(key);
          } else {
            _selectedQuantities[key] = maxAllowed;
          }
        }
      }
    });

    for (final k in toRemove) {
      _selectedQuantities.remove(k);
    }

    if (clampedAny && mounted) {
      ShowMessage.warning(context, 'Item quantities adjusted to available stock.');
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
            barcode: invItem.barcode,
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
      if (_sortByReceiptOrder && _scannedReceiptOrder.isNotEmpty) {
        final keyA = '${a.productSource}:${a.productId}';
        final keyB = '${b.productSource}:${b.productId}';
        final idxA = _scannedReceiptOrder.indexOf(keyA);
        final idxB = _scannedReceiptOrder.indexOf(keyB);
        if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
        if (idxA != -1) return -1;
        if (idxB != -1) return 1;
      }
      return Helperfunctions.compareProducts(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
        productIdA: a.productId,
        productIdB: b.productId,
        categoryA: a.category,
        categoryB: b.category,
      );
    });
    return result;
  }

  Future<void> _promptQuantityDialog(InventoryItem item, {List<InventoryItem>? allInventory}) async {
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    final itemKey = _itemKey(item);
    final rawReceiptText = _scannedRawTexts[itemKey];
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

                      if (rawReceiptText != null && rawReceiptText.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 16, color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SCANNED ON DOCUMENT:',
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4, color: Colors.amber.shade900),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      rawReceiptText.trim(),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ),
                              if (allInventory != null)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                                  label: const Text('Correct AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showCorrectionDialog(itemKey: itemKey, allInventory: allInventory);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],

                      if (item.incomingQuantity > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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
    final Map<String, InventoryItem> byKey = {for (final item in allInventory) _itemKey(item): item};
    if (_selectedQuantities.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final rawItems = _buildOrderItemsList(allInventory);
            if (rawItems.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(sheetCtx)) Navigator.pop(sheetCtx);
              });
              return const SizedBox.shrink();
            }

            final promoEval = _evaluatePromos(rawItems, allInventory);
            final items = [...rawItems, ...promoEval.freeItems];
            final colorScheme = Theme.of(sheetCtx).colorScheme;
            final grossAmount = promoEval.grossAmount;
            final discountAmount = promoEval.discountAmount;
            final totalAmount = promoEval.netAmount;
            final totalUnits = items.fold<int>(0, (acc, i) => acc + i.pickedQuantity);

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.70,
              minChildSize: 0.4,
              maxChildSize: 0.95,
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
                            onPressed: () async {
                              final confirmed = await ShowMessage.confirm(
                                sheetCtx,
                                title: 'Clear Order',
                                message: 'Are you sure you want to remove all items from this order?',
                                confirmText: 'Clear All',
                                isDestructive: true,
                              );
                              if (confirmed) {
                                setState(() => _selectedQuantities.clear());
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              }
                            },
                            icon: Icon(Icons.delete_sweep_outlined, size: 20, color: colorScheme.error),
                            label: Text('Clear', style: TextStyle(fontSize: 13, color: colorScheme.error)),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isSelecta = item.productSource == 'selecta';
                            final itemKey = '${item.productSource}:${item.productId}';
                            final invItem = byKey[itemKey];
                            final maxAllowed = invItem != null ? _getMaxOrderableQty(invItem) : 9999;
                            final receiptIdx = _scannedReceiptOrder.indexOf(itemKey);
                            final receiptNum = receiptIdx != -1 ? receiptIdx + 1 : null;
                            final rawReceiptText = _scannedRawTexts[itemKey];
                            final isItemCorrected = _correctedReceiptKeys.contains(itemKey);

                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Row 1: Image + Full-Width Title + Delete Icon ──
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CachedProductImage(imageUrl: item.imageUrl, size: 44, borderRadius: 8),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                if (receiptNum != null)
                                                  Container(
                                                    margin: const EdgeInsets.only(right: 6),
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: isItemCorrected ? Colors.blue.shade100 : Colors.amber.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: (isItemCorrected ? Colors.blue.shade400 : Colors.amber.shade400).withValues(
                                                          alpha: 0.6,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '#$receiptNum',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w800,
                                                        color: isItemCorrected ? Colors.blue.shade900 : Colors.amber.shade900,
                                                      ),
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: Text(
                                                    item.productName,
                                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, height: 1.25),
                                                    maxLines: 4,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (rawReceiptText != null && rawReceiptText.trim().isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber.shade200),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.receipt_long_outlined, size: 11, color: Colors.amber.shade900),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        'Scanned: ${rawReceiptText.trim()}',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (isItemCorrected)
                                                      Text(
                                                        '✓ Corrected',
                                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 20),
                                        tooltip: 'Remove',
                                        onPressed: () {
                                          if (invItem != null) {
                                            _setSelectedQty(invItem, 0);
                                          } else {
                                            setState(() => _selectedQuantities.remove(itemKey));
                                          }
                                          setSheetState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // ── Row 2: Price / Subtotal on Left + Stepper on Right ──
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(left: 54),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.isFreeReward
                                                  ? 'Reward Item • ₱0.00'
                                                  : '${isSelecta ? 'Selecta' : 'Other'} • ${_currencyFormat.format(item.sellingPrice)} each',
                                              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                            ),
                                            Text(
                                              item.isFreeReward ? 'FREE' : _currencyFormat.format(item.lineTotal),
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: item.isFreeReward ? Colors.green.shade700 : colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (item.isFreeReward)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.green.shade200),
                                          ),
                                          child: Text(
                                            '${item.pickedQuantity} Free Unit${item.pickedQuantity == 1 ? '' : 's'}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                          ),
                                        )
                                      else
                                        Container(
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                              onTap: () {
                                                HapticFeedback.lightImpact();
                                                if (invItem != null) {
                                                  _setSelectedQty(invItem, item.pickedQuantity - 1);
                                                } else {
                                                  final newQ = item.pickedQuantity - 1;
                                                  setState(() {
                                                    if (newQ <= 0) {
                                                      _selectedQuantities.remove(itemKey);
                                                    } else {
                                                      _selectedQuantities[itemKey] = newQ;
                                                    }
                                                  });
                                                }
                                                setSheetState(() {});
                                              },
                                              child: SizedBox(
                                                width: 30,
                                                height: 32,
                                                child: Icon(
                                                  item.pickedQuantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                                  size: 16,
                                                  color: item.pickedQuantity == 1 ? colorScheme.error : colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () async {
                                                if (invItem != null) {
                                                  await _promptQuantityDialog(invItem, allInventory: allInventory);
                                                  setSheetState(() {});
                                                }
                                              },
                                              child: Container(
                                                constraints: const BoxConstraints(minWidth: 32),
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '${item.pickedQuantity}',
                                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                                              onTap: item.pickedQuantity < maxAllowed
                                                  ? () {
                                                      HapticFeedback.lightImpact();
                                                      if (invItem != null) {
                                                        _setSelectedQty(invItem, item.pickedQuantity + 1);
                                                      } else {
                                                        setState(() => _selectedQuantities[itemKey] = item.pickedQuantity + 1);
                                                      }
                                                      setSheetState(() {});
                                                    }
                                                  : null,
                                              child: SizedBox(
                                                width: 30,
                                                height: 32,
                                                child: Icon(
                                                  Icons.add_rounded,
                                                  size: 16,
                                                  color: item.pickedQuantity < maxAllowed ? colorScheme.primary : colorScheme.outlineVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 16),
                      if (promoEval.hints.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.tips_and_updates_outlined, size: 16, color: Colors.blue.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  promoEval.hints.first,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (discountAmount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Gross Total', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                            Text(
                              _currencyFormat.format(grossAmount),
                              style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        for (final applied in promoEval.appliedPromos)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(applied.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.green.shade700)),
                              Text(
                                '-${_currencyFormat.format(applied.discountAmount)}',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                      ],
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

    final rawOrderItems = _buildOrderItemsList(allInventory);
    if (rawOrderItems.isEmpty) {
      ShowMessage.error(context, 'Please select at least 1 product to book an order.');
      return;
    }

    final promoEval = _evaluatePromos(rawOrderItems, allInventory);

    // Q1 Rule: promo should not be booked and the app should show that an item is out of stock.
    if (promoEval.isOOSBlocked) {
      ShowMessage.error(
        context,
        'Promo bundle cannot be booked because item(s) or free reward(s) are out of stock: ${promoEval.oosItemNames.join(", ")}',
      );
      return;
    }

    final orderItems = [...rawOrderItems, ...promoEval.freeItems];
    final storeName = _storeController.text.trim();
    final grossAmount = promoEval.grossAmount;
    final discountAmount = promoEval.discountAmount;
    final totalAmount = promoEval.netAmount;
    final appliedPromos = promoEval.appliedPromos;
    final totalUnits = orderItems.fold<int>(0, (acc, i) => acc + i.pickedQuantity);

    final promoSuffix = discountAmount > 0 ? ' (Includes ${_currencyFormat.format(discountAmount)} promo savings)' : '';
    final confirmed = await ShowMessage.confirm(
      context,
      title: _isEditing ? 'Update Order' : 'Save Order',
      message: _isEditing
          ? 'Save changes to $storeName order (${orderItems.length} items, $totalUnits units • ${_currencyFormat.format(totalAmount)})$promoSuffix?'
          : 'Save order for $storeName (${orderItems.length} items, $totalUnits units • ${_currencyFormat.format(totalAmount)})$promoSuffix?\n\n'
                'This will book the order for delivery and hold reserved stock.',
      icon: Icons.check_circle_outline,
      confirmText: 'Save Order',
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: _isEditing ? 'Updating Order' : 'Saving Order',
      subtitle: _isEditing ? 'Updating order for $storeName...' : 'Reserving inventory stock for $storeName...',
    );
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
            grossAmount: grossAmount,
            discountAmount: discountAmount,
            appliedPromos: appliedPromos,
          );
        } else {
          await OfflineSyncService.instance.enqueueOrderCreation(
            storeName: storeName,
            selectedDate: _selectedDate,
            items: orderItems,
            remarks: _remarksController.text,
            grossAmount: grossAmount,
            discountAmount: discountAmount,
            appliedPromos: appliedPromos,
          );
        }
        if (!mounted) return;
        Helperfunctions.showLoading(context: context, showLoading: false);
        ShowMessage.warning(context, 'Saved to Offline Queue! Order will automatically sync once connectivity is restored.');
        Navigator.pop(context);
        return;
      }

      if (_isEditing) {
        final updated = await _deliveryController
            .updateBookedOrder(
              deliveryId: widget.deliveryID,
              currentDelivery: widget.existingDelivery!,
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
              grossAmount: grossAmount,
              discountAmount: discountAmount,
              appliedPromos: appliedPromos,
            )
            .timeout(const Duration(seconds: 30));
        if (!mounted) return;
        Helperfunctions.showLoading(context: context, showLoading: false);
        ShowMessage.success(context, 'Order updated for $storeName!');
        Navigator.pop(context, updated);
      } else {
        final createdResult = await _deliveryController
            .createBookedOrder(
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
              grossAmount: grossAmount,
              discountAmount: discountAmount,
              appliedPromos: appliedPromos,
            )
            .timeout(const Duration(seconds: 30));
        if (!mounted) return;
        Helperfunctions.showLoading(context: context, showLoading: false);
        ShowMessage.success(context, 'Order booked for $storeName!');
        Navigator.pop(context, createdResult.delivery);
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      // Only treat genuine offline network failures where the write never reached Firestore as offline.
      // Do NOT enqueue on timeout exceptions since in-flight server writes may have already completed.
      final isOffline =
          e is SocketException ||
          (e is FirebaseException && (e.code == 'unavailable' || e.code == 'network-request-failed')) ||
          errStr.contains('socketexception') ||
          errStr.contains('network is unreachable') ||
          errStr.contains('client is offline');

      if (isOffline) {
        try {
          if (_isEditing) {
            await OfflineSyncService.instance.enqueueOrderUpdate(
              deliveryId: widget.deliveryID,
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
              grossAmount: grossAmount,
              discountAmount: discountAmount,
              appliedPromos: appliedPromos,
            );
          } else {
            await OfflineSyncService.instance.enqueueOrderCreation(
              storeName: storeName,
              selectedDate: _selectedDate,
              items: orderItems,
              remarks: _remarksController.text,
              grossAmount: grossAmount,
              discountAmount: discountAmount,
              appliedPromos: appliedPromos,
            );
          }
          if (!mounted) return;
          Helperfunctions.showLoading(context: context, showLoading: false);
          ShowMessage.warning(context, 'Saved to Offline Queue! Order will automatically sync once connectivity is restored.');
          Navigator.pop(context);
          return;
        } catch (_) {
          // If local enqueuing also fails, fall through to error message
        }
      }

      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
        if (e is TimeoutException || errStr.contains('timeout')) {
          ShowMessage.error(context, 'Order save timed out. Please check your network or verify in Picklist before retrying.');
        } else {
          ShowMessage.error(context, 'Failed to save order: $e');
        }
      }
    } finally {
      if (mounted) {
        Helperfunctions.showLoading(context: context, showLoading: false);
        setState(() => _isSaving = false);
      }
    }
  }

  // ============================================================
  // Scan Receipt (alternative to manual product selection)
  // ============================================================

  /// Reads a receipt from the external booking app with Sedy AI and fills the cart.
  /// Scanned quantities are capped to available stock; the user reviews before saving.
  Future<void> _onScanReceipt(List<InventoryItem> allInventory) async {
    if (_isScanning || _isSaving) return;
    _searchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (_storeController.text.trim().isEmpty) {
      await _showStoreAndDateModal();
      if (!mounted || _storeController.text.trim().isEmpty) return;
    }
    if (allInventory.isEmpty) {
      ShowMessage.error(context, 'Product catalog is still loading. Please try again.');
      return;
    }

    final files = await ReceiptScanFlow.pickImages(context);
    if (!mounted || files == null || files.isEmpty) return;

    var mergeMode = ReceiptMergeMode.replace;
    if (_selectedQuantities.isNotEmpty) {
      final choice = await ReceiptScanFlow.askMergeMode(context, existingSkuCount: _selectedQuantities.length);
      if (!mounted || choice == null) return;
      mergeMode = choice;
    }

    setState(() => _isScanning = true);
    final statusNotifier = ValueNotifier<String>('Step 1/3: Preparing receipt images...');
    Helperfunctions.showLoading(
      context: context,
      showLoading: true,
      message: 'Scanning Order Receipt',
      subtitle: 'Please wait while Sedy AI reads your receipt.',
      statusNotifier: statusNotifier,
    );

    ReceiptScanOutcome outcome;
    try {
      final (result, knownMappings) = await ReceiptScanFlow.extract(
        files: files,
        allInventory: allInventory,
        onProgress: (status) => statusNotifier.value = status,
      );
      if (!mounted) return;

      statusNotifier.value = 'Step 3/3: Matching with product catalog...';
      Helperfunctions.showLoading(showLoading: false);
      setState(() => _isScanning = false);

      outcome = await ReceiptScanFlow.resolve(context, result: result, allInventory: allInventory, knownMappings: knownMappings);
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ShowMessage.error(context, 'AI: ${e.toString().replaceAll('Exception: ', '')}');
      }
      return;
    } finally {
      Helperfunctions.showLoading(showLoading: false);
    }

    if (!mounted) return;

    if (outcome.lines.isEmpty) {
      ShowMessage.warning(context, 'No products were read from the receipt. Please try a clearer image.');
      return;
    }

    // Merge duplicate rows of the same product, preserving receipt order.
    final Map<String, ScannedReceiptLine> merged = {};
    for (final line in outcome.lines) {
      final key = _itemKey(line.item);
      final prev = merged[key];
      merged[key] = prev == null ? line : ScannedReceiptLine(item: line.item, quantity: prev.quantity + line.quantity, rawText: prev.rawText);
    }

    final Map<String, int> next = mergeMode == ReceiptMergeMode.add ? Map.of(_selectedQuantities) : {};
    final List<ReceiptCapNote> capped = [];
    int addedSkus = 0;
    int addedUnits = 0;

    for (final entry in merged.entries) {
      final item = entry.value.item;
      final existing = next[entry.key] ?? 0;
      final desired = existing + entry.value.quantity;
      final maxAllowed = _getMaxOrderableQty(item);
      final applied = desired.clamp(0, maxAllowed < 0 ? 0 : maxAllowed);

      if (applied < desired) {
        capped.add(ReceiptCapNote(item: item, requested: entry.value.quantity, applied: (applied - existing).clamp(0, applied)));
      }
      if (applied > 0) {
        next[entry.key] = applied;
      } else {
        next.remove(entry.key);
      }
      final gained = applied - existing;
      if (gained > 0) {
        addedSkus++;
        addedUnits += gained;
      }
    }

    final List<String> scannedKeys = [];
    final Map<String, String> scannedTexts = {};
    for (final entry in merged.entries) {
      scannedKeys.add(entry.key);
      scannedTexts[entry.key] = entry.value.rawText;
    }

    setState(() {
      _selectedQuantities
        ..clear()
        ..addAll(next);
      _scannedReceiptOrder
        ..clear()
        ..addAll(scannedKeys);
      _scannedRawTexts
        ..clear()
        ..addAll(scannedTexts);
      _correctedReceiptKeys.clear();
      _sortByReceiptOrder = true;
      _searchController.clear();
      _searchQuery = '';
      _selectedCategoryFilter = _selectedQuantities.isNotEmpty ? 'selected' : 'all';
    });

    if (!mounted) return;
    await ReceiptScanFlow.showSummary(
      context,
      skuCount: addedSkus,
      unitCount: addedUnits,
      capped: capped,
      skipped: outcome.skipped,
      scannedLines: _buildScannedReceiptLines(allInventory),
      getScannedLines: () => _buildScannedReceiptLines(allInventory),
      correctedKeys: _correctedReceiptKeys,
      getCorrectedKeys: () => _correctedReceiptKeys,
      onCorrectLine: (line) async {
        final key = _itemKey(line.item);
        await _showCorrectionDialog(itemKey: key, allInventory: allInventory);
      },
    );
  }

  /// Builds the current list of scanned receipt lines reflecting any user corrections.
  List<ScannedReceiptLine> _buildScannedReceiptLines(List<InventoryItem> allInventory) {
    final Map<String, InventoryItem> byKey = {for (final item in allInventory) _itemKey(item): item};
    final List<ScannedReceiptLine> lines = [];
    for (final key in _scannedReceiptOrder) {
      final inv = byKey[key];
      final qty = _selectedQuantities[key] ?? 0;
      if (inv != null && qty > 0) {
        lines.add(ScannedReceiptLine(item: inv, quantity: qty, rawText: _scannedRawTexts[key] ?? inv.productName));
      }
    }
    return lines;
  }

  // ============================================================
  // Scanned Receipt AI Correction Dialog
  // ============================================================

  /// Mirrors the Purchase Order AI correction sheet: lets the dealer compare
  /// the full document raw text with the device product, replace it with another
  /// catalog product, adjust quantity, and remember the mapping for future scans.
  Future<void> _showCorrectionDialog({required String itemKey, required List<InventoryItem> allInventory}) async {
    final Map<String, InventoryItem> byKey = {for (final item in allInventory) _itemKey(item): item};
    final currentItem = byKey[itemKey];
    if (currentItem == null) return;

    final rawReceiptText = _scannedRawTexts[itemKey] ?? '';
    final receiptIdx = _scannedReceiptOrder.indexOf(itemKey);
    final receiptNum = receiptIdx != -1 ? receiptIdx + 1 : 1;
    final searchCtrl = TextEditingController();

    InventoryItem? replacementProduct;
    int updatedQty = _selectedQuantities[itemKey] ?? 1;
    if (updatedQty < 1) updatedQty = 1;
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
                        (i) =>
                            i.isActive &&
                            (i.productName.toLowerCase().contains(filter.toLowerCase()) ||
                                i.itemCode.toLowerCase().contains(filter.toLowerCase()) ||
                                i.category.toLowerCase().contains(filter.toLowerCase())),
                      )
                      .take(10)
                      .toList();

            final effectiveProduct = replacementProduct;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
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
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), shape: BoxShape.circle),
                            child: const Icon(Icons.edit_note_rounded, color: Colors.blue, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Correct Item #$receiptNum', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(
                                  'Item #$receiptNum • Receipt Product Verification',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Dedicated Actual Scanned Product Name Callout Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                    'PRINTED ON DOCUMENT / RECEIPT:',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.amber.shade900, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rawReceiptText.isNotEmpty ? rawReceiptText : currentItem.productName,
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
                                effectiveProduct != null ? 'New Product to Assign:' : 'Currently Assigned Device Product:',
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
                                    CachedProductImage(imageUrl: effectiveProduct?.imageUrl ?? currentItem.imageUrl, size: 44),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            effectiveProduct?.productName ?? currentItem.productName,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'Selling Price: ${_currencyFormat.format(effectiveProduct?.sellingPrice ?? currentItem.sellingPrice)}',
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
                                          '✓ Selected',
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
                                    'Quantity on Receipt:',
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

                              // Search & Replace
                              Text(
                                'Replace with different product:',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: searchCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Search catalog by product name or item code...',
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
                                        dense: true,
                                        leading: CachedProductImage(imageUrl: item.imageUrl, size: 32),
                                        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        subtitle: Text(
                                          _currencyFormat.format(item.sellingPrice),
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
                              if (rawReceiptText.isNotEmpty)
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
                                    'AI will automatically assign "$rawReceiptText" to this product next time.',
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
                                _selectedQuantities.remove(itemKey);
                                _scannedReceiptOrder.remove(itemKey);
                                _scannedRawTexts.remove(itemKey);
                                _correctedReceiptKeys.remove(itemKey);
                              });
                              ShowMessage.info(context, 'Line item removed from order.');
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
                          AsyncFilledButton(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: const Text('Save Changes'),
                            onPressed: () async {
                              final finalProduct = replacementProduct;
                              final finalKey = finalProduct != null ? _itemKey(finalProduct) : itemKey;

                              setState(() {
                                if (finalProduct != null) {
                                  _selectedQuantities.remove(itemKey);
                                  _scannedRawTexts.remove(itemKey);
                                  _correctedReceiptKeys.remove(itemKey);

                                  if (receiptIdx != -1) {
                                    _scannedReceiptOrder[receiptIdx] = finalKey;
                                  } else if (!_scannedReceiptOrder.contains(finalKey)) {
                                    _scannedReceiptOrder.add(finalKey);
                                  }

                                  final maxAllowed = _getMaxOrderableQty(finalProduct);
                                  final appliedQty = maxAllowed <= 0 ? updatedQty : updatedQty.clamp(1, maxAllowed);
                                  _selectedQuantities[finalKey] = appliedQty;
                                  _scannedRawTexts[finalKey] = rawReceiptText;
                                  _correctedReceiptKeys.add(finalKey);
                                } else {
                                  final maxAllowed = _getMaxOrderableQty(currentItem);
                                  final appliedQty = maxAllowed <= 0 ? updatedQty : updatedQty.clamp(1, maxAllowed);
                                  _selectedQuantities[itemKey] = appliedQty;
                                  _correctedReceiptKeys.add(itemKey);
                                }
                              });

                              Navigator.pop(ctx);

                              if (rememberCorrection && rawReceiptText.isNotEmpty) {
                                await ReceiptScanFlow.mappingService.saveOrUpdateMapping(
                                  rawSupplierText: rawReceiptText,
                                  product: finalProduct ?? currentItem,
                                );
                              }

                              if (mounted) ShowMessage.success(context, 'Item #$receiptNum updated!');
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedStoreName = _storeController.text.trim();
    final hasSelectedStore = selectedStoreName.isNotEmpty;

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryController.getActiveInventoryStream(),
      builder: (context, snapshot) {
        final allInventory = (snapshot.data ?? []).where((item) => item.isActive).toList();
        _latestInventory = allInventory;

        final rawOrderItems = _buildOrderItemsList(allInventory);
        final promoEval = _evaluatePromos(rawOrderItems, allInventory);
        final orderItems = [...rawOrderItems, ...promoEval.freeItems];
        final grossAmount = promoEval.grossAmount;
        final discountAmount = promoEval.discountAmount;
        final totalAmount = promoEval.netAmount;
        final totalUnits = orderItems.fold<int>(0, (acc, i) => acc + i.pickedQuantity);
        final unplacedCount = allInventory
            .where(
              (i) =>
                  i.source == InventoryProductSource.selecta &&
                  ProductTag.isBestSeller(i.tag) &&
                  !_placedProductNames.contains(i.productName.trim().toLowerCase()),
            )
            .length;

        final isLocked = _isSaving || _isScanning;

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
                title: 'Discard Order Changes?',
                message: 'You have unsaved changes or items selected in this order. Are you sure you want to go back and discard them?',
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
              title: _isEditing ? 'Edit Order' : 'Store Order',
              subtitle: hasSelectedStore ? '$selectedStoreName • ${_formatAppBarDate(_selectedDate)}' : 'Order for a Hapi Store',
              centerTitle: false,
              onBackPressed: isLocked ? () => ShowMessage.warning(context, 'Operation in progress. Please wait.') : null,
              actions: [_buildOverflowMenuAction(allInventory: allInventory, unplacedCount: unplacedCount, colorScheme: colorScheme)],
            ),
            bottomNavigationBar: (hasSelectedStore && !ScreenSize.isTabletLandscape(context))
                ? _buildStickyOrderSummaryBar(
                    colorScheme: colorScheme,
                    allInventory: allInventory,
                    skuCount: orderItems.length,
                    totalUnits: totalUnits,
                    totalAmount: totalAmount,
                    grossAmount: grossAmount,
                    discountAmount: discountAmount,
                  )
                : null,
            body: Stack(
              children: [
                if (!hasSelectedStore)
                  _buildSelectStorePrompt(colorScheme, allInventory)
                else if (ScreenSize.isTabletLandscape(context))
                  _buildTabletLandscapeView(
                    colorScheme: colorScheme,
                    allInventory: allInventory,
                    orderItems: orderItems,
                    totalAmount: totalAmount,
                    grossAmount: grossAmount,
                    discountAmount: discountAmount,
                    appliedPromos: promoEval.appliedPromos,
                    hints: promoEval.hints,
                    promoEval: promoEval,
                    totalUnits: totalUnits,
                    unplacedCount: unplacedCount,
                    snapshot: snapshot,
                  )
                else
                  Column(
                    children: [
                      _buildSearchAndFiltersHeader(colorScheme, orderItems.length, unplacedCount),
                      Expanded(
                        child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                            ? const Center(child: CircularProgressIndicator())
                            : _buildUnifiedProductList(
                                allInventory: allInventory,
                                colorScheme: colorScheme,
                                promoEval: promoEval,
                              ),
                      ),
                    ],
                  ),
                if (_isScanning) Positioned.fill(child: _buildScanningOverlay(colorScheme)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFiltersHeader(ColorScheme colorScheme, int selectedCount, int unplacedCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: false,
                    onTapOutside: (_) => _searchFocusNode.unfocus(),
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Search product, SKU, or category...',
                      hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search, size: 22, color: colorScheme.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
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
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  selected: _selectedCategoryFilter == 'all',
                  label: Text(
                    'All',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'all' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (_) => setState(() => _selectedCategoryFilter = 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _selectedCategoryFilter == 'selected',
                  label: Text(
                    'Selected ($selectedCount)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'selected' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'selected' : 'all'),
                ),
                if (unplacedCount > 0) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const Key('unplaced_recommendations_chip'),
                    selected: _selectedCategoryFilter == 'unplaced',
                    label: Text(
                      'Unplaced ($unplacedCount)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _selectedCategoryFilter == 'unplaced' ? colorScheme.onPrimary : colorScheme.onSurface,
                      ),
                    ),
                    selectedColor: const Color(0xFFD97706),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'unplaced' : 'all'),
                  ),
                ],
                const SizedBox(width: 8),
                FilterChip(
                  selected: _selectedCategoryFilter == 'best_sellers',
                  label: Text(
                    '⭐ Best Sellers',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'best_sellers' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'best_sellers' : 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _selectedCategoryFilter == 'by_case',
                  label: Text(
                    '📦 By Case',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'by_case' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'by_case' : 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _selectedCategoryFilter == 'by_piece',
                  label: Text(
                    '🍦 By Piece',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'by_piece' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'by_piece' : 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _selectedCategoryFilter == 'other',
                  label: Text(
                    '🛒 Other Products',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedCategoryFilter == 'other' ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _selectedCategoryFilter = val ? 'other' : 'all'),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('hide_out_of_stock_chip'),
                  selected: _hideOutOfStock,
                  avatar: Icon(
                    _hideOutOfStock ? Icons.visibility_off_rounded : Icons.visibility_outlined,
                    size: 16,
                    color: _hideOutOfStock ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    'Hide Out of Stock',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _hideOutOfStock ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  onSelected: (val) => setState(() => _hideOutOfStock = val),
                ),
                if (_scannedReceiptOrder.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    key: const Key('receipt_order_toggle_chip'),
                    selected: _sortByReceiptOrder,
                    avatar: Icon(
                      _sortByReceiptOrder ? Icons.receipt_long_outlined : Icons.category_outlined,
                      size: 15,
                      color: _sortByReceiptOrder ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                    ),
                    label: Text(
                      _sortByReceiptOrder ? 'Receipt Sequence (#1–#${_scannedReceiptOrder.length})' : 'Catalog Grouping',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _sortByReceiptOrder ? Colors.amber.shade900 : colorScheme.onSurface,
                      ),
                    ),
                    selectedColor: Colors.amber.shade100,
                    side: BorderSide(
                      color: _sortByReceiptOrder ? Colors.amber.shade400 : colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    onSelected: (val) => setState(() => _sortByReceiptOrder = val),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLandscapeView({
    required ColorScheme colorScheme,
    required List<InventoryItem> allInventory,
    required List<OrderItem> orderItems,
    required double totalAmount,
    required double grossAmount,
    required double discountAmount,
    required List<AppliedPromo> appliedPromos,
    required List<String> hints,
    required PromoEvaluationResult promoEval,
    required int totalUnits,
    required int unplacedCount,
    required AsyncSnapshot<List<InventoryItem>> snapshot,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Product Catalog (flex: 6)
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _buildSearchAndFiltersHeader(colorScheme, orderItems.length, unplacedCount),
              const Divider(height: 1),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : _buildUnifiedProductList(
                        allInventory: allInventory,
                        colorScheme: colorScheme,
                        promoEval: promoEval,
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Right: Cart Summary Panel (flex: 4)
        Expanded(
          flex: 4,
          child: _buildTabletCartPane(
            colorScheme: colorScheme,
            allInventory: allInventory,
            orderItems: orderItems,
            totalAmount: totalAmount,
            grossAmount: grossAmount,
            discountAmount: discountAmount,
            appliedPromos: appliedPromos,
            hints: hints,
            totalUnits: totalUnits,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletCartPane({
    required ColorScheme colorScheme,
    required List<InventoryItem> allInventory,
    required List<OrderItem> orderItems,
    required double totalAmount,
    required double grossAmount,
    required double discountAmount,
    required List<AppliedPromo> appliedPromos,
    required List<String> hints,
    required int totalUnits,
  }) {
    final Map<String, InventoryItem> byKey = {for (final item in allInventory) _itemKey(item): item};

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
                Icon(Icons.shopping_bag_outlined, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Order Cart (${orderItems.length} SKU${orderItems.length == 1 ? '' : 's'} • $totalUnits units)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (orderItems.isNotEmpty)
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
                        title: 'Clear Order',
                        message: 'Are you sure you want to remove all items from this order?',
                        confirmText: 'Clear All',
                        isDestructive: true,
                      );
                      if (confirmed && mounted) {
                        setState(() => _selectedQuantities.clear());
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Store & Delivery Date Info Card
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surface,
            child: InkWell(
              onTap: _showStoreAndDateModal,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _storeController.text.trim(),
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                'Delivery: ${_formatAppBarDate(_selectedDate)}',
                                style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // Items List
          Expanded(
            child: orderItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          'No items in cart',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pick products from the catalog on the left.',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: orderItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = orderItems[index];
                      final isReward = item.isFreeReward;
                      final itemKey = '${item.productSource}:${item.productId}';
                      final invItem = byKey[itemKey];
                      final maxAllowed = invItem != null ? _getMaxOrderableQty(invItem) : 9999;
                      final receiptIdx = _scannedReceiptOrder.indexOf(itemKey);
                      final receiptNum = receiptIdx != -1 ? receiptIdx + 1 : null;
                      final isItemCorrected = _correctedReceiptKeys.contains(itemKey);
                      final itemTotal = item.sellingPrice * item.pickedQuantity;

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isReward ? const Color(0xFFF0FDF4) : colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isReward
                                ? const Color(0xFF86EFAC)
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
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
                                  Row(
                                    children: [
                                      if (isReward)
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF16A34A),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'FREE REWARD',
                                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white),
                                          ),
                                        )
                                      else if (receiptNum != null)
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isItemCorrected ? Colors.blue.shade100 : Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: (isItemCorrected ? Colors.blue.shade400 : Colors.amber.shade400).withValues(alpha: 0.6),
                                            ),
                                          ),
                                          child: Text(
                                            '#$receiptNum',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: isItemCorrected ? Colors.blue.shade900 : Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          item.productName,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (isReward)
                                    const Text(
                                      'Auto-applied reward item',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                                    )
                                  else
                                    Text(
                                      '${_currencyFormat.format(item.sellingPrice)} each',
                                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Stepper or Reward Tag
                            if (isReward)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Text(
                                  'Qty: ${item.pickedQuantity}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                                ),
                              )
                            else
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
                                        if (invItem != null) {
                                          _setSelectedQty(invItem, item.pickedQuantity - 1);
                                        }
                                      },
                                    ),
                                    InkWell(
                                      onTap: invItem != null ? () => _promptQuantityDialog(invItem, allInventory: allInventory) : null,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Text(
                                          '${item.pickedQuantity}',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 14),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 30),
                                      onPressed: item.pickedQuantity < maxAllowed
                                          ? () {
                                              HapticFeedback.lightImpact();
                                              if (invItem != null) {
                                                _setSelectedQty(invItem, item.pickedQuantity + 1);
                                              }
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 65,
                              child: Text(
                                isReward ? 'FREE' : _currencyFormat.format(itemTotal),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isReward ? const Color(0xFF16A34A) : colorScheme.primary,
                                ),
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
                if (hints.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hints.first,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (appliedPromos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: appliedPromos.map((p) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, size: 12, color: Color(0xFF16A34A)),
                              const SizedBox(width: 4),
                              Text(
                                p.promoTitle,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Units:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                    Text('$totalUnits', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (discountAmount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gross Total:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      Text(
                        _currencyFormat.format(grossAmount),
                        style: TextStyle(
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Promo Savings:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                      ),
                      Text(
                        '-${_currencyFormat.format(discountAmount)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      _currencyFormat.format(totalAmount),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AsyncFilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      _isEditing ? 'Save Changes' : 'Book Order',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isScanning ? null : () => _onSaveOrder(allInventory),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningOverlay(ColorScheme colorScheme) {
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(color: colorScheme.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 14),
              const Text('Sedy AI is reading the receipt…', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Matching products to your catalog', style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowMenuAction({required List<InventoryItem> allInventory, required int unplacedCount, required ColorScheme colorScheme}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PopupMenuButton<String>(
            key: const Key('book_order_overflow_menu'),
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.white),
            tooltip: 'Order options',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: colorScheme.surface,
            elevation: 8,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onSelected: (value) {
              switch (value) {
                case 'scan':
                  if (!_isScanning) {
                    _onScanReceipt(allInventory);
                  }
                  break;
                case 'recommendations':
                  final storeName = _storeController.text.trim();
                  if (storeName.isEmpty) {
                    ShowMessage.info(context, 'Please select a store first.');
                    return;
                  }
                  StoreRecommendationsModal.show(
                    context: context,
                    storeName: storeName,
                    actionButtonLabel: 'Filter Unplaced in Catalog',
                    onProceedToBookOrder: () {
                      setState(() => _selectedCategoryFilter = 'unplaced');
                    },
                  );
                  break;
                case 'store_date':
                  _showStoreAndDateModal();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                key: const Key('book_order_menu_scan_receipt'),
                value: 'scan',
                child: Row(
                  children: [
                    Icon(Icons.document_scanner_outlined, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Scan Receipt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text('Extract with Sedy AI', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                key: const Key('book_order_menu_recommendations'),
                value: 'recommendations',
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 20, color: Color(0xFFD97706)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Recommendations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            unplacedCount > 0 ? '$unplacedCount unplaced this month' : 'View store guide & depot stock',
                            style: TextStyle(fontSize: 11, color: unplacedCount > 0 ? const Color(0xFFD97706) : colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (unplacedCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '$unplacedCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                key: const Key('book_order_menu_store_date'),
                value: 'store_date',
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined, size: 20, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Store & Delivery Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          if (_storeController.text.trim().isNotEmpty)
                            Text(
                              _storeController.text.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (unplacedCount > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
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
      if (dateChanged) {
        _clampQuantitiesToAvailableStock(_latestInventory);
      }
      if (storeChanged || dateChanged) {
        _loadPlacedProductsForStore(_storeController.text, _selectedDate);
      }
    }
  }

  Widget _buildSelectStorePrompt(ColorScheme colorScheme, List<InventoryItem> allInventory) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
            AsyncFilledButton.icon(
              onPressed: _showStoreAndDateModal,
              icon: const Icon(Icons.storefront_outlined, size: 20),
              label: const Text('Choose Store & Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            AsyncOutlinedButton.icon(
              key: const Key('book_order_scan_receipt_prompt_button'),
              onPressed: _isScanning ? null : () => _onScanReceipt(allInventory),
              icon: const Icon(Icons.document_scanner_outlined, size: 20),
              label: const Text('Scan Receipt Instead', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
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
    return Helperfunctions.compareProducts(
      nameA: a.productName,
      priceA: a.sellingPrice,
      nameB: b.productName,
      priceB: b.sellingPrice,
      productIdA: a.id,
      productIdB: b.id,
      categoryA: a.category,
      categoryB: b.category,
    );
  }

  Widget _buildUnifiedProductList({
    required List<InventoryItem> allInventory,
    required ColorScheme colorScheme,
    required PromoEvaluationResult promoEval,
  }) {
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
      if (_selectedCategoryFilter == 'selected' && _getSelectedQty(item) <= 0) return false;
      if (_hideOutOfStock && _getMaxOrderableQty(item) <= 0) return false;

      // Category filter:
      if (_selectedCategoryFilter == 'unplaced') {
        if (item.source != InventoryProductSource.selecta ||
            !ProductTag.isBestSeller(item.tag) ||
            _placedProductNames.contains(item.productName.trim().toLowerCase())) {
          return false;
        }
      } else if (_selectedCategoryFilter == 'best_sellers') {
        if (item.source != InventoryProductSource.selecta || !ProductTag.isBestSeller(item.tag)) {
          return false;
        }
      } else if (_selectedCategoryFilter == 'by_case') {
        if (item.source != InventoryProductSource.selecta ||
            ProductTag.isBestSeller(item.tag) ||
            !item.category.trim().toLowerCase().contains('case')) {
          return false;
        }
      } else if (_selectedCategoryFilter == 'by_piece') {
        if (item.source != InventoryProductSource.selecta ||
            ProductTag.isBestSeller(item.tag) ||
            item.category.trim().toLowerCase().contains('case')) {
          return false;
        }
      } else if (_selectedCategoryFilter == 'other') {
        if (item.source == InventoryProductSource.selecta) {
          return false;
        }
      }

      // Expanded search: check name, SKU/barcode (itemCode), category, and tag
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery;
        final nameMatch = item.productName.toLowerCase().contains(query);
        final codeMatch = item.itemCode.toLowerCase().contains(query);
        final categoryMatch = item.category.toLowerCase().contains(query);
        final tagMatch = item.tag.toLowerCase().contains(query);
        if (!nameMatch && !codeMatch && !categoryMatch && !tagMatch) {
          return false;
        }
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      String emptyMessage;
      if (_searchQuery.isNotEmpty) {
        emptyMessage = 'No products matching "$_searchQuery"';
      } else if (_selectedCategoryFilter == 'selected') {
        emptyMessage = 'No selected products found';
      } else if (_selectedCategoryFilter == 'unplaced') {
        emptyMessage = 'All target best-sellers have already been placed for this store!';
      } else if (_hideOutOfStock) {
        emptyMessage = 'No in-stock products found';
      } else {
        emptyMessage = 'No products found in this category';
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
              ),
              if (_selectedCategoryFilter != 'all' || _hideOutOfStock || _searchQuery.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedCategoryFilter = 'all';
                      _hideOutOfStock = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reset Filters'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final entries = <_BookOrderListEntry>[];

    // Show pinned promos at the top of the general catalog
    if (_selectedCategoryFilter == 'all' && _searchQuery.isEmpty && _activePromos.isNotEmpty) {
      entries.add(
        _BookOrderPromoSectionEntry(
          promos: _activePromos,
          promoEval: promoEval,
        ),
      );
    }

    if (_selectedCategoryFilter == 'unplaced') {
      final sortedUnplaced = filtered.toList()..sort(_compareProducts);
      if (sortedUnplaced.isNotEmpty) {
        entries.add(
          _BookOrderHeaderEntry(
            title: 'Unplaced Best Sellers',
            count: sortedUnplaced.length,
            icon: Icons.lightbulb_outline_rounded,
            accentColor: const Color(0xFFD97706),
          ),
        );
        for (final p in sortedUnplaced) {
          entries.add(_BookOrderCardEntry(p));
        }
      }
    } else if (_sortByReceiptOrder && _scannedReceiptOrder.isNotEmpty) {
      final receiptItems = filtered.where((i) => _scannedReceiptOrder.contains(_itemKey(i))).toList()
        ..sort((a, b) => _scannedReceiptOrder.indexOf(_itemKey(a)).compareTo(_scannedReceiptOrder.indexOf(_itemKey(b))));
      final otherItems = filtered.where((i) => !_scannedReceiptOrder.contains(_itemKey(i))).toList()..sort(_compareProducts);

      if (receiptItems.isNotEmpty) {
        entries.add(
          _BookOrderHeaderEntry(
            title: 'Scanned Receipt Sequence',
            count: receiptItems.length,
            icon: Icons.receipt_long_outlined,
            accentColor: Colors.amber.shade900,
          ),
        );
        for (final p in receiptItems) {
          entries.add(_BookOrderCardEntry(p));
        }
      }

      if (otherItems.isNotEmpty) {
        entries.add(
          _BookOrderHeaderEntry(
            title: 'Additional Products',
            count: otherItems.length,
            icon: Icons.playlist_add_rounded,
            accentColor: const Color(0xFF475569),
          ),
        );
        for (final p in otherItems) {
          entries.add(_BookOrderCardEntry(p));
        }
      }
    } else {
      final selectaFiltered = filtered.where((i) => i.source == InventoryProductSource.selecta).toList();
      final otherFiltered = filtered.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(_compareProducts);

      final bestSellerProducts = selectaFiltered.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
      final nonBestSellerSelecta = selectaFiltered.where((i) => !ProductTag.isBestSeller(i.tag)).toList();

      final caseProducts = nonBestSellerSelecta.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
      final pieceProducts = nonBestSellerSelecta.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

      // 1. Best Sellers at the top
      if (bestSellerProducts.isNotEmpty) {
        entries.add(
          _BookOrderHeaderEntry(
            title: 'Best Sellers',
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
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _BookOrderPromoSectionEntry) {
          return PromoCardsSection(
            promos: entry.promos,
            usedCounts: _storePromoUsage,
            appliedPromos: entry.promoEval.appliedPromos,
            cartQuantities: {
              for (final e in _selectedQuantities.entries) e.key.split(':').last: e.value,
            },
            currencyFormat: _currencyFormat,
            onAddBundle: (promo) => _addPromoBundleToCart(promo, allInventory),
          );
        } else if (entry is _BookOrderHeaderEntry) {
          return _buildCategorySectionHeader(
            title: entry.title,
            count: entry.count,
            icon: entry.icon,
            accentColor: entry.accentColor,
            colorScheme: colorScheme,
          );
        } else if (entry is _BookOrderCardEntry) {
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildProductOrderCard(entry.item, colorScheme, allInventory));
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildProductOrderCard(InventoryItem item, ColorScheme colorScheme, List<InventoryItem> allInventory) {
    final key = _itemKey(item);
    final receiptIdx = _scannedReceiptOrder.indexOf(key);
    final receiptNum = receiptIdx != -1 ? receiptIdx + 1 : null;
    final rawText = _scannedRawTexts[key];

    return ProductOrderCard(
      item: item,
      selectedQty: _getSelectedQty(item),
      maxOrderable: _getMaxOrderableQty(item),
      isPlaced: _placedProductNames.contains(item.productName.trim().toLowerCase()),
      currencyFormat: _currencyFormat,
      receiptIndex: receiptNum,
      rawReceiptText: rawText,
      isCorrected: _correctedReceiptKeys.contains(key),
      isFutureDelivery: _isFutureDeliveryDate,
      onCorrectAi: rawText != null ? () => _showCorrectionDialog(itemKey: key, allInventory: allInventory) : null,
      onTap: () => _promptQuantityDialog(item, allInventory: allInventory),
      onIncrement: () {
        HapticFeedback.lightImpact();
        final current = _getSelectedQty(item);
        _setSelectedQty(item, current + 1);
      },
      onDecrement: () {
        HapticFeedback.lightImpact();
        final current = _getSelectedQty(item);
        _setSelectedQty(item, current - 1);
      },
    );
  }

  Widget _buildStickyOrderSummaryBar({
    required ColorScheme colorScheme,
    required List<InventoryItem> allInventory,
    required int skuCount,
    required int totalUnits,
    required double totalAmount,
    required double grossAmount,
    required double discountAmount,
  }) {
    return StickyOrderSummaryBar(
      skuCount: skuCount,
      totalUnits: totalUnits,
      totalAmount: totalAmount,
      grossAmount: grossAmount,
      discountAmount: discountAmount,
      currencyFormat: _currencyFormat,
      isSaving: _isSaving || _isScanning,
      onTapCartSummary: () => _showCartSummarySheet(allInventory),
      onSaveOrder: () => _onSaveOrder(allInventory),
    );
  }
}

sealed class _BookOrderListEntry {}

class _BookOrderPromoSectionEntry extends _BookOrderListEntry {
  final List<Promo> promos;
  final PromoEvaluationResult promoEval;
  _BookOrderPromoSectionEntry({required this.promos, required this.promoEval});
}

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
