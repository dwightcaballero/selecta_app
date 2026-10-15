import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/van_sell_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/thermal_printer_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';

class VanSellPage extends StatefulWidget {
  final String? preselectedStoreName;

  const VanSellPage({super.key, this.preselectedStoreName});

  @override
  State<VanSellPage> createState() => _VanSellPageState();
}

class _VanSellPageState extends State<VanSellPage> {
  final VanSellController _controller = VanSellController();
  final ThermalPrinterService _printerService = ThermalPrinterService();

  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _storeSearchController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();

  VanLoad? _activeVanLoad;
  StreamSubscription? _vanLoadSub;

  List<Hapistore> _allStores = [];
  Set<String> _buyingStoreNames = {};
  bool _isLoadingStores = true;
  bool _filterOnlyNonBuying = false;

  Hapistore? _selectedStore;
  final Map<String, int> _sellQuantities = {}; // productId -> quantity
  final Map<String, TextEditingController> _qtyControllers = {};

  String _paymentMethod = 'Cash'; // 'Cash' | 'Online' | 'Credit'
  bool _isSaving = false;
  String _productSearchQuery = '';

  bool get _hasUnsavedChanges =>
      _selectedStore != null || _sellQuantities.values.any((q) => q > 0) || _remarksController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _subscribeActiveVanLoad();
    _loadStoresAndBuyingStatus();
  }

  @override
  void dispose() {
    _vanLoadSub?.cancel();
    _remarksController.dispose();
    _cashReceivedController.dispose();
    _storeSearchController.dispose();
    _productSearchController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _subscribeActiveVanLoad() {
    _vanLoadSub = _controller.streamActiveVanLoad().listen((load) {
      if (!mounted) return;
      setState(() {
        _activeVanLoad = load;
        // Clamp existing sell quantities against new available quantities if load changed
        if (load != null) {
          final Map<String, int> available = {
            for (final vi in load.items) vi.productId: vi.availableQuantity
          };
          _sellQuantities.removeWhere((id, qty) {
            final max = available[id] ?? 0;
            return max <= 0;
          });
          _sellQuantities.forEach((id, qty) {
            final max = available[id] ?? 0;
            if (qty > max) {
              _sellQuantities[id] = max;
              _getQtyController(id).text = '$max';
            }
          });
        }
      });
    });
  }

  Future<void> _loadStoresAndBuyingStatus() async {
    setState(() => _isLoadingStores = true);
    try {
      final buyingSet = await _controller.getBuyingStoreNamesCurrentMonth();
      final storeSnap = await FirebaseFirestore.instance
          .collection(HAPISTORE_COLLECTION_REF)
          .orderBy('storeName')
          .get();

      final stores = storeSnap.docs
          .map((d) => Hapistore.fromJson(d.data()))
          .where((s) => s.storeName.trim().isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _allStores = stores;
        _buyingStoreNames = buyingSet;
        _isLoadingStores = false;

        if (widget.preselectedStoreName != null && widget.preselectedStoreName!.isNotEmpty) {
          _selectedStore = stores
              .where((s) => s.storeName.trim().toLowerCase() == widget.preselectedStoreName!.trim().toLowerCase())
              .firstOrNull;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingStores = false);
    }
  }

  bool _isNonBuying(Hapistore store) {
    return !_buyingStoreNames.contains(store.storeName.trim().toLowerCase());
  }

  TextEditingController _getQtyController(String productId) {
    return _qtyControllers.putIfAbsent(productId, () {
      final initialVal = _sellQuantities[productId] ?? 0;
      return TextEditingController(text: initialVal > 0 ? '$initialVal' : '');
    });
  }

  void _updateQuantity(String productId, int newQty, int availableMax) {
    final clamped = newQty.clamp(0, availableMax);
    setState(() {
      if (clamped <= 0) {
        _sellQuantities.remove(productId);
        _getQtyController(productId).text = '';
      } else {
        _sellQuantities[productId] = clamped;
        _getQtyController(productId).text = '$clamped';
      }
    });
  }

  int get _totalSellUnits {
    return _sellQuantities.values.fold<int>(0, (acc, q) => acc + q);
  }

  double get _totalSellAmount {
    if (_activeVanLoad == null) return 0.0;
    double total = 0.0;
    final Map<String, double> priceMap = {
      for (final vi in _activeVanLoad!.items) vi.productId: vi.sellingPrice
    };
    for (final entry in _sellQuantities.entries) {
      final price = priceMap[entry.key] ?? 0.0;
      total += price * entry.value;
    }
    return total;
  }

  List<OrderItem> _buildOrderItems() {
    if (_activeVanLoad == null) return [];
    final List<OrderItem> items = [];
    for (final entry in _sellQuantities.entries) {
      if (entry.value <= 0) continue;
      final vanItem = _activeVanLoad!.items.where((i) => i.productId == entry.key).firstOrNull;
      if (vanItem != null) {
        items.add(OrderItem(
          productId: vanItem.productId,
          productName: vanItem.productName,
          imageUrl: vanItem.imageUrl,
          barcode: vanItem.barcode,
          productSource: vanItem.productSource,
          category: vanItem.category,
          tag: vanItem.tag,
          buyingPrice: vanItem.buyingPrice,
          sellingPrice: vanItem.sellingPrice,
          orderedQuantity: entry.value,
          pickedQuantity: entry.value,
          returnedQuantity: 0,
          isPicked: true,
        ));
      }
    }
    return items;
  }

  Future<void> _processSale() async {
    if (_activeVanLoad == null) {
      SnackBarWidget.error(context, 'No active Van Load found. Please ask Dealer to load van first.');
      return;
    }

    if (_selectedStore == null) {
      SnackBarWidget.error(context, 'Please select a registered Hapi Store.');
      return;
    }

    final items = _buildOrderItems();
    if (items.isEmpty) {
      SnackBarWidget.error(context, 'Please add at least 1 product from van stock.');
      return;
    }

    final total = _totalSellAmount;
    double cashAmt = 0.0;
    double onlineAmt = 0.0;
    double creditAmt = 0.0;

    if (_paymentMethod == 'Cash') {
      cashAmt = total;
    } else if (_paymentMethod == 'Online') {
      onlineAmt = total;
    } else if (_paymentMethod == 'Credit') {
      creditAmt = total;
    }

    setState(() => _isSaving = true);
    try {
      final result = await _controller.completeVanSale(
        vanLoad: _activeVanLoad!,
        store: _selectedStore!,
        items: items,
        paymentMethod: _paymentMethod,
        cashAmount: cashAmt,
        onlineAmount: onlineAmt,
        creditAmount: creditAmt,
        remarks: _remarksController.text.trim(),
      );

      if (!mounted) return;

      SnackBarWidget.success(context, 'Van Sale recorded for ${_selectedStore!.storeName}!');

      // Prompt for thermal print
      await _promptThermalPrint(result.delivery, result.deliveryId);

      // Reset form for next customer
      if (mounted) {
        setState(() {
          _selectedStore = null;
          _sellQuantities.clear();
          for (final c in _qtyControllers.values) {
            c.clear();
          }
          _remarksController.clear();
          _cashReceivedController.clear();
        });
      }
    } catch (e) {
      if (mounted) SnackBarWidget.error(context, 'Failed to complete sale: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _promptThermalPrint(Delivery delivery, String deliveryId) async {
    final shouldPrint = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.print_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Print Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Would you like to print the receipt for ${delivery.storeName} (${Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount)})?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later / Skip')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Print Now'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (shouldPrint == true && mounted) {
      try {
        final success = await _printerService.printReceipt(
          delivery: delivery,
          dealerName: 'Selecta Ops',
          deliveryId: deliveryId,
        );
        if (mounted) {
          if (success) {
            SnackBarWidget.success(context, 'Receipt printed successfully!');
          } else {
            SnackBarWidget.error(context, 'Failed to send print job to thermal printer.');
          }
        }
      } catch (e) {
        if (mounted) SnackBarWidget.error(context, 'Print error: $e');
      }
    }
  }

  void _showStoreSelectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final query = _storeSearchController.text.trim().toLowerCase();
          final filtered = _allStores.where((s) {
            final matchesQuery = query.isEmpty ||
                s.storeName.toLowerCase().contains(query) ||
                s.storeAddress.toLowerCase().contains(query);
            final isNonBuying = _isNonBuying(s);
            final matchesFilter = !_filterOnlyNonBuying || isNonBuying;
            return matchesQuery && matchesFilter;
          }).toList();

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Select Registered Hapi Store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                // Search bar
                TextField(
                  controller: _storeSearchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search store name or address...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setModalState(() {}),
                ),
                const SizedBox(height: 8),
                // Filter chip for Non-Buying stores
                Row(
                  children: [
                    FilterChip(
                      label: const Text('⚠️ Non-Buying Stores (0 orders this month)'),
                      selected: _filterOnlyNonBuying,
                      selectedColor: Colors.amber.shade100,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _filterOnlyNonBuying ? Colors.amber.shade900 : Colors.black87,
                      ),
                      onSelected: (val) {
                        setModalState(() => _filterOnlyNonBuying = val);
                        setState(() => _filterOnlyNonBuying = val);
                      },
                    ),
                  ],
                ),
                const Divider(height: 16),
                Expanded(
                  child: _isLoadingStores
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(child: Text('No stores found', style: TextStyle(color: Colors.grey.shade600)))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final store = filtered[i];
                            final isNonBuying = _isNonBuying(store);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isNonBuying ? Colors.amber.shade50 : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.storefront_outlined,
                                  color: isNonBuying ? Colors.amber.shade800 : Colors.teal,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(store.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                                  ),
                                  if (isNonBuying)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'NON-BUYING',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.amber.shade900),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                store.storeAddress.isNotEmpty ? store.storeAddress : 'No address specified',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(modalCtx);
                                setState(() {
                                  _selectedStore = store;
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSaving) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Van Sale?',
            message: 'You have unsaved items or store selection. Are you sure you want to go back and discard this sale?',
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
        title: 'Van Sell',
        subtitle: _activeVanLoad != null
            ? '${_activeVanLoad!.totalAvailableUnits} units available on van'
            : 'Sell From Van Stock',
        showBackButton: true,
      ),
      body: _activeVanLoad == null
          ? _buildNoActiveLoadState(theme)
          : _buildVanSellForm(theme),
      bottomNavigationBar: _activeVanLoad != null
          ? _buildBottomBar(theme)
          : null,
    ),
    );
  }

  Widget _buildNoActiveLoadState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_transfer_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('No Active Van Load Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Stocks must be loaded onto the van before you can start selling.\nPlease ask the Dealer to create and confirm a Van Load.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Check Again'),
              onPressed: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVanSellForm(ThemeData theme) {
    final vanItems = _activeVanLoad!.items.where((i) {
      final matchesSearch = _productSearchQuery.isEmpty ||
          i.productName.toLowerCase().contains(_productSearchQuery.toLowerCase());
      return matchesSearch && i.availableQuantity > 0;
    }).toList();

    return Column(
      children: [
        // Store Selection Section
        Container(
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Customer Store:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                  if (_selectedStore != null && _isNonBuying(_selectedStore!))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('NON-BUYING STORE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _showStoreSelectionModal,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _selectedStore == null ? Colors.teal : Colors.grey.shade300, width: _selectedStore == null ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, color: _selectedStore != null ? Colors.teal : Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedStore != null ? _selectedStore!.storeName : 'Select Registered Hapi Store...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _selectedStore != null ? Colors.black87 : Colors.grey.shade600,
                              ),
                            ),
                            if (_selectedStore != null && _selectedStore!.storeAddress.isNotEmpty)
                              Text(
                                _selectedStore!.storeAddress,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Search in van inventory
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _productSearchController,
                  onChanged: (val) => setState(() => _productSearchQuery = val.trim()),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search products on van...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Products on Van
        Expanded(
          child: vanItems.isEmpty
              ? Center(
                  child: Text(
                    _activeVanLoad!.items.isEmpty
                        ? 'No products loaded on van.'
                        : 'No available products match search.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  itemCount: vanItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = vanItems[i];
                    final currentQty = _sellQuantities[item.productId] ?? 0;
                    final qtyCtrl = _getQtyController(item.productId);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CachedProductImage(imageUrl: item.imageUrl, size: 44),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        'Van Stock: ${item.availableQuantity}',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Stepper
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.teal),
                                onPressed: currentQty > 0
                                    ? () => _updateQuantity(item.productId, currentQty - 1, item.availableQuantity)
                                    : null,
                              ),
                              SizedBox(
                                width: 44,
                                height: 36,
                                child: TextField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    hintText: '0',
                                  ),
                                  onChanged: (val) {
                                    final parsed = int.tryParse(val) ?? 0;
                                    _updateQuantity(item.productId, parsed, item.availableQuantity);
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                                onPressed: currentQty < item.availableQuantity
                                    ? () => _updateQuantity(item.productId, currentQty + 1, item.availableQuantity)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Payment Method Selector
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment Method:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final method in ['Cash', 'Online', 'Credit'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Center(
                            child: Text(
                              method,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: _paymentMethod == method ? Colors.teal.shade900 : Colors.black87,
                              ),
                            ),
                          ),
                          selected: _paymentMethod == method,
                          selectedColor: Colors.teal.shade100,
                          onSelected: (sel) {
                            if (sel) setState(() => _paymentMethod = method);
                          },
                        ),
                      ),
                    ),
                ],
              ),
              if (_paymentMethod == 'Credit')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.purple.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Will be recorded as Unpaid Credit receivable for this store.',
                        style: TextStyle(fontSize: 11.5, color: Colors.purple.shade800, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_totalSellUnits items', style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(_totalSellAmount),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.teal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _isSaving ? 'Processing...' : 'Complete & Print',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: _isSaving ? null : _processSale,
            ),
          ],
        ),
      ),
    );
  }
}
