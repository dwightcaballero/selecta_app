import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/controllers/van_load_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';

class VanLoadPage extends StatefulWidget {
  final String? initialVanLoadId;

  const VanLoadPage({super.key, this.initialVanLoadId});

  @override
  State<VanLoadPage> createState() => _VanLoadPageState();
}

class _VanLoadPageState extends State<VanLoadPage> {
  final VanLoadController _vanLoadController = VanLoadController();
  final InventoryController _inventoryController = InventoryController();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isCreatingNew = false;
  bool _isLoading = false;
  bool _isDealer = false;

  VanLoad? _currentVanLoad;
  StreamSubscription? _activeLoadSub;
  StreamSubscription? _inventorySub;

  List<InventoryItem> _allInventoryItems = [];
  final Map<String, int> _loadedQuantities = {}; // productId -> quantity
  final Map<String, TextEditingController> _qtyControllers = {};

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _subscribeInventory();
    _subscribeActiveVanLoad();
  }

  void _checkUserRole() async {
    final isDealer = await _vanLoadController.checkIsDealer();
    if (!mounted) return;
    setState(() {
      _isDealer = isDealer;
    });
  }

  @override
  void dispose() {
    _activeLoadSub?.cancel();
    _inventorySub?.cancel();
    _remarksController.dispose();
    _searchController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _subscribeInventory() {
    _inventorySub = _inventoryController.getActiveInventoryStream().listen((items) {
      if (!mounted) return;
      setState(() {
        _allInventoryItems = items.where((i) => i.isActive).toList();
      });
    });
  }

  void _subscribeActiveVanLoad() {
    if (widget.initialVanLoadId != null) {
      _loadSpecificVanLoad(widget.initialVanLoadId!);
    } else {
      _activeLoadSub = _vanLoadController.streamActiveVanLoad().listen((activeLoad) {
        if (!mounted) return;
        if (!_isCreatingNew) {
          setState(() {
            _currentVanLoad = activeLoad;
            if (activeLoad != null) {
              _remarksController.text = activeLoad.remarks;
              _syncLoadedQuantitiesFromVanLoad(activeLoad);
            }
          });
        }
      });
    }
  }

  Future<void> _loadSpecificVanLoad(String id) async {
    setState(() => _isLoading = true);
    final load = await _vanLoadController.getVanLoad(id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _currentVanLoad = load;
      if (load != null) {
        _remarksController.text = load.remarks;
        _syncLoadedQuantitiesFromVanLoad(load);
      }
    });
  }

  void _syncLoadedQuantitiesFromVanLoad(VanLoad load) {
    _loadedQuantities.clear();
    for (final item in load.items) {
      _loadedQuantities[item.productId] = item.loadedQuantity;
      _getQtyController(item.productId).text = item.loadedQuantity > 0 ? '${item.loadedQuantity}' : '';
    }
  }

  TextEditingController _getQtyController(String productId) {
    return _qtyControllers.putIfAbsent(productId, () {
      final initialVal = _loadedQuantities[productId] ?? 0;
      return TextEditingController(text: initialVal > 0 ? '$initialVal' : '');
    });
  }

  void _updateQuantity(String productId, int newQty, int maxStock) {
    final clamped = newQty.clamp(0, maxStock);
    setState(() {
      if (clamped <= 0) {
        _loadedQuantities.remove(productId);
        _getQtyController(productId).text = '';
      } else {
        _loadedQuantities[productId] = clamped;
        _getQtyController(productId).text = '$clamped';
      }
    });
  }

  int get _totalLoadedUnits {
    return _loadedQuantities.values.fold<int>(0, (acc, q) => acc + q);
  }

  double get _totalLoadedAmount {
    double total = 0.0;
    for (final entry in _loadedQuantities.entries) {
      final item = _allInventoryItems.where((i) => i.id == entry.key).firstOrNull;
      if (item != null) {
        total += item.sellingPrice * entry.value;
      }
    }
    return total;
  }

  List<VanLoadItem> _buildVanLoadItems() {
    final List<VanLoadItem> items = [];
    for (final entry in _loadedQuantities.entries) {
      if (entry.value <= 0) continue;
      final prod = _allInventoryItems.where((i) => i.id == entry.key).firstOrNull;
      if (prod != null) {
        items.add(VanLoadItem(
          productId: prod.id,
          productName: prod.productName,
          imageUrl: prod.imageUrl,
          barcode: prod.barcode,
          productSource: prod.productSource,
          category: prod.category,
          tag: prod.tag,
          buyingPrice: prod.buyingPrice,
          sellingPrice: prod.sellingPrice,
          loadedQuantity: entry.value,
          soldQuantity: 0,
          returnedQuantity: 0,
        ));
      }
    }
    return items;
  }

  // ignore: unused_element
  Future<void> _saveDraftManifest() async {
    final items = _buildVanLoadItems();
    if (items.isEmpty) {
      SnackBarWidget.error(context, 'Please add at least one product with quantity > 0');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final now = Timestamp.now();
      final user = _vanLoadController.getCurrentUserDisplayName();

      if (_currentVanLoad == null || _currentVanLoad!.id == null) {
        final newLoad = VanLoad(
          date: Timestamp.fromDate(_selectedDate),
          status: VanLoadStatus.draft,
          items: items,
          remarks: _remarksController.text.trim(),
          totalLoadedAmount: _totalLoadedAmount,
          createdDate: now,
          createdBy: user,
          lastUpdatedDate: now,
          lastUpdatedBy: user,
        );
        final id = await _vanLoadController.createDraftVanLoad(newLoad);
        newLoad.id = id;
        _currentVanLoad = newLoad;
      } else {
        final updated = _currentVanLoad!.copyWith(
          items: items,
          remarks: _remarksController.text.trim(),
          totalLoadedAmount: _totalLoadedAmount,
          lastUpdatedDate: now,
          lastUpdatedBy: user,
        );
        await _vanLoadController.updateDraftVanLoad(_currentVanLoad!.id!, updated);
        _currentVanLoad = updated;
      }

      if (mounted) {
        SnackBarWidget.success(context, 'Draft Van Load saved successfully.');
        setState(() {
          _isCreatingNew = false;
        });
      }
    } catch (e) {
      if (mounted) SnackBarWidget.error(context, 'Failed to save draft: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAndDeductWarehouseStock() async {
    if (!_isDealer) {
      SnackBarWidget.error(context, 'Only dealers are allowed to create and confirm van load records.');
      return;
    }
    final items = _buildVanLoadItems();
    if (items.isEmpty) {
      SnackBarWidget.error(context, 'Please add at least one product with quantity > 0');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.local_shipping_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text('Confirm & Load Van', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are loading $_totalLoadedUnits units (${Helperfunctions.formatDoubleAmountForDisplay(_totalLoadedAmount)}) onto the van.',
              style: const TextStyle(fontSize: 14.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warehouse stock will be deducted immediately with "Van Load" movement logs.',
                      style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('Proceed with loading?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Deduct Stock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final now = Timestamp.now();
      final user = _vanLoadController.getCurrentUserDisplayName();

      VanLoad targetLoad;
      if (_currentVanLoad == null || _currentVanLoad!.id == null) {
        final newLoad = VanLoad(
          date: Timestamp.fromDate(_selectedDate),
          status: VanLoadStatus.draft,
          items: items,
          remarks: _remarksController.text.trim(),
          totalLoadedAmount: _totalLoadedAmount,
          createdDate: now,
          createdBy: user,
          lastUpdatedDate: now,
          lastUpdatedBy: user,
        );
        final id = await _vanLoadController.createDraftVanLoad(newLoad);
        newLoad.id = id;
        targetLoad = newLoad;
      } else {
        targetLoad = _currentVanLoad!.copyWith(
          items: items,
          remarks: _remarksController.text.trim(),
          totalLoadedAmount: _totalLoadedAmount,
          lastUpdatedDate: now,
          lastUpdatedBy: user,
        );
      }

      await _vanLoadController.confirmAndLoadVan(vanLoad: targetLoad);

      if (mounted) {
        SnackBarWidget.success(context, 'Van loaded successfully! Stock has been deducted from warehouse.');
        setState(() {
          _isCreatingNew = false;
        });
      }
    } catch (e) {
      if (mounted) SnackBarWidget.error(context, 'Failed to confirm load: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEodSettlementModal(VanLoad vanLoad) {
    final Map<String, int> returnedCounts = {
      for (final item in vanLoad.items) item.productId: item.availableQuantity
    };
    final Map<String, TextEditingController> returnControllers = {
      for (final item in vanLoad.items)
        item.productId: TextEditingController(text: '${item.availableQuantity}')
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final totalReturnedUnits = returnedCounts.values.fold<int>(0, (acc, q) => acc + q);
          double totalReturnedValue = 0.0;
          for (final item in vanLoad.items) {
            final qty = returnedCounts[item.productId] ?? 0;
            totalReturnedValue += item.sellingPrice * qty;
          }

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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.assignment_turned_in_outlined, color: Colors.teal),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('End of Day Van Settlement', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          Text('Return unsold products back to warehouse stock', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Summary card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStat('Loaded', '${vanLoad.totalLoadedUnits}'),
                      _buildMiniStat('Sold', '${vanLoad.totalSoldUnits}', color: Colors.green.shade700),
                      _buildMiniStat('Returning', '$totalReturnedUnits', color: Colors.teal.shade800),
                      _buildMiniStat('Return Value', Helperfunctions.formatDoubleAmountForDisplay(totalReturnedValue), color: Colors.teal.shade800),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Verify Returned Quantities:', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.separated(
                    itemCount: vanLoad.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = vanLoad.items[i];
                      final retCtrl = returnControllers[item.productId]!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CachedProductImage(imageUrl: item.imageUrl, size: 40),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                  Text(
                                    'Loaded: ${item.loadedQuantity} • Sold: ${item.soldQuantity} • Remaining: ${item.availableQuantity}',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              height: 38,
                              child: TextField(
                                controller: retCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  hintText: '0',
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val) ?? 0;
                                  final clamped = parsed.clamp(0, item.availableQuantity);
                                  setModalState(() {
                                    returnedCounts[item.productId] = clamped;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                  label: Text(
                    'Confirm Return ($totalReturnedUnits Units) & Complete',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: () async {
                    Navigator.pop(modalCtx);
                    setState(() => _isLoading = true);
                    try {
                      final updatedItems = vanLoad.items.map((item) {
                        final retQty = returnedCounts[item.productId] ?? item.availableQuantity;
                        return item.copyWith(returnedQuantity: retQty);
                      }).toList();

                      await _vanLoadController.completeVanLoadAndReturnStock(
                        vanLoad: vanLoad,
                        returnedItems: updatedItems,
                      );

                      if (mounted) {
                        SnackBarWidget.success(context, 'Van Load completed! Unsold items returned to warehouse stock.');
                        setState(() {
                          _currentVanLoad = null;
                        });
                      }
                    } catch (e) {
                      if (mounted) SnackBarWidget.error(context, 'Failed to complete van load: $e');
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? Colors.black87)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _statusChip(String status) {
    Color bg = Colors.grey.shade100;
    Color fg = Colors.grey.shade800;
    IconData icon = Icons.info_outline;

    switch (status) {
      case VanLoadStatus.draft:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        icon = Icons.edit_note;
        break;
      case VanLoadStatus.loaded:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        icon = Icons.local_shipping_outlined;
        break;
      case VanLoadStatus.inRoute:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        icon = Icons.directions_car_filled_outlined;
        break;
      case VanLoadStatus.completed:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        icon = Icons.check_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Van Load',
        subtitle: _isCreatingNew
            ? 'New Van Manifest'
            : (_currentVanLoad != null ? 'Manifest • ${DateFormat('d MMM yyyy').format(_currentVanLoad!.date.toDate())}' : 'Manifests & Loading'),
        showBackButton: true,
        actions: [
          if (!_isCreatingNew && _currentVanLoad != null && _currentVanLoad!.status == VanLoadStatus.draft)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Delete Draft',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Draft Load?'),
                    content: const Text('This will discard this draft manifest.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true && _currentVanLoad?.id != null) {
                  await _vanLoadController.deleteDraftVanLoad(_currentVanLoad!.id!, _currentVanLoad!);
                  setState(() => _currentVanLoad = null);
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isCreatingNew || (_currentVanLoad != null && _currentVanLoad!.status == VanLoadStatus.draft)
              ? _buildManifestEditor(theme)
              : _buildDashboardView(theme),
      bottomNavigationBar: (_isCreatingNew || (_currentVanLoad != null && _currentVanLoad!.status == VanLoadStatus.draft))
          ? _buildBottomActionBar(theme)
          : null,
    );
  }

  Widget _buildDashboardView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active load card
          if (_currentVanLoad != null) ...[
            _buildActiveLoadCard(theme, _currentVanLoad!),
            const SizedBox(height: 20),
          ] else ...[
            _buildNoActiveLoadCard(theme),
            const SizedBox(height: 20),
          ],

          // History list header
          const Text('Recent Van Loads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          StreamBuilder<List<VanLoad>>(
            stream: _vanLoadController.streamVanLoads(limit: 20),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()));
              }

              final loads = snapshot.data ?? [];
              if (loads.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text('No past van loads recorded yet.', style: TextStyle(color: Colors.grey.shade600)),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: loads.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final load = loads[index];
                  final isCurrent = _currentVanLoad?.id == load.id;

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCurrent ? Colors.teal : Colors.grey.shade200,
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: ListTile(
                      onTap: () {
                        setState(() {
                          _currentVanLoad = load;
                          _syncLoadedQuantitiesFromVanLoad(load);
                        });
                      },
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCurrent ? Colors.teal.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.local_shipping_rounded, color: isCurrent ? Colors.teal : Colors.grey.shade700),
                      ),
                      title: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Van Load',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusChip(load.status),
                        ],
                      ),
                      subtitle: Text(
                        '${DateFormat('d MMM yyyy, h:mm a').format(load.date.toDate())} • ${load.totalLoadedUnits} units (${Helperfunctions.formatDoubleAmountForDisplay(load.totalLoadedAmount)})',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveLoadCard(ThemeData theme, VanLoad load) {
    final progress = load.totalLoadedUnits > 0 ? (load.totalSoldUnits / load.totalLoadedUnits).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.teal.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.local_shipping_rounded, color: Colors.teal, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active Van Load', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          Text(DateFormat('EEE, d MMM yyyy').format(load.date.toDate()), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(load.status),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Sales Progress: ${load.totalSoldUnits} / ${load.totalLoadedUnits} units sold',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.teal.shade50,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniStat('Loaded', '${load.totalLoadedUnits} units'),
              _buildMiniStat('Sold Value', Helperfunctions.formatDoubleAmountForDisplay(load.calculatedSoldAmount), color: Colors.green.shade700),
              _buildMiniStat('Remaining', '${load.totalAvailableUnits} units', color: Colors.teal.shade800),
            ],
          ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              if (load.status == VanLoadStatus.draft)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit Draft'),
                    onPressed: () => setState(() => _isCreatingNew = true),
                  ),
                )
              else if (load.isActive) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal)),
                    icon: const Icon(Icons.list_alt_rounded, size: 18),
                    label: const Text('View Manifest'),
                    onPressed: () => setState(() => _isCreatingNew = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                    label: const Text('EOD Settlement'),
                    onPressed: () => _showEodSettlementModal(load),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveLoadCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.no_transfer_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No Active Van Load', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            _isDealer
                ? 'Create a manifest to load products from warehouse inventory onto the van.'
                : 'Only dealers are allowed to create a van load record.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          if (_isDealer) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Create New Van Load', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                setState(() {
                  _isCreatingNew = true;
                  _currentVanLoad = null;
                  _loadedQuantities.clear();
                  for (final c in _qtyControllers.values) {
                    c.clear();
                  }
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuantityDialog(InventoryItem item, int currentQty, int maxAllowed) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final defaultQty = currentQty > 0 ? currentQty : (maxAllowed >= 1 ? 1 : 0);
    final initialText = defaultQty > 0 ? '$defaultQty' : '';
    final controller = TextEditingController(text: initialText)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);
    final entered = await showDialog<int>(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void setVal(int v) {
              final clamped = v.clamp(0, maxAllowed);
              final text = clamped > 0 ? '$clamped' : '';
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection(baseOffset: 0, extentOffset: text.length),
              );
              setDialogState(() {});
            }

            return AlertDialog(
              title: Text(item.productName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Warehouse Stock: $maxAllowed',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '0',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(label: const Text('+1'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 1)),
                      ActionChip(label: const Text('+5'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 5)),
                      ActionChip(label: const Text('+10'), onPressed: () => setVal((int.tryParse(controller.text) ?? 0) + 10)),
                      ActionChip(label: const Text('Max'), onPressed: () => setVal(maxAllowed)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    final qty = int.tryParse(controller.text.trim()) ?? 0;
                    Navigator.pop(dCtx, qty);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (entered != null) {
      _updateQuantity(item.id, entered, maxAllowed);
    }
  }

  Future<void> _showLoadedSummaryModal(ThemeData theme) async {
    final isDraft = _currentVanLoad == null || _currentVanLoad!.status == VanLoadStatus.draft;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final loadedItems = _allInventoryItems.where((i) => (_loadedQuantities[i.id] ?? 0) > 0).toList();
            loadedItems.sort((a, b) => Helperfunctions.compareBySrpAndName(
                  nameA: a.productName,
                  priceA: a.sellingPrice,
                  nameB: b.productName,
                  priceB: b.sellingPrice,
                ));

            final skuCount = loadedItems.length;
            final totalUnits = _totalLoadedUnits;
            final totalAmount = _totalLoadedAmount;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
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
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.local_shipping_outlined, color: Colors.teal.shade800, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Loaded Manifest Summary ($skuCount SKU${skuCount == 1 ? '' : 's'} • $totalUnits units)',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDraft && loadedItems.isNotEmpty) ...[
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red.shade700),
                              tooltip: 'Clear All',
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: sheetCtx,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Clear Loaded Items'),
                                    content: const Text('Are you sure you want to remove all loaded quantities from this manifest?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(dCtx, true),
                                        child: const Text('Clear All'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  setState(() {
                                    _loadedQuantities.clear();
                                    for (final ctrl in _qtyControllers.values) {
                                      ctrl.text = '';
                                    }
                                  });
                                  setSheetState(() {});
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Confirm Load', style: TextStyle(fontSize: 12.5)),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _confirmAndDeductWarehouseStock();
                              },
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 16),
                      if (loadedItems.isEmpty)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                const Text('No Products Loaded Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  'Set quantities on items in the catalog to review them here.',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            itemCount: loadedItems.length,
                            separatorBuilder: (_, _) => const Divider(height: 14),
                            itemBuilder: (context, index) {
                              final item = loadedItems[index];
                              final currentQty = _loadedQuantities[item.id] ?? 0;
                              final availableWarehouseStock = item.availableQuantity;
                              final lineTotal = item.sellingPrice * currentQty;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CachedProductImage(imageUrl: item.imageUrl, size: 44, borderRadius: 8),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.productName,
                                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, height: 1.25),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${item.isSelecta ? 'Selecta' : 'Other'} • ${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice)} each',
                                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isDraft)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                                          tooltip: 'Remove',
                                          onPressed: () {
                                            _updateQuantity(item.id, 0, availableWarehouseStock);
                                            setSheetState(() {});
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(left: 54),
                                        child: Text(
                                          Helperfunctions.formatDoubleAmountForDisplay(lineTotal),
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.teal.shade800),
                                        ),
                                      ),
                                      if (isDraft)
                                        Container(
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.grey.shade300),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                                onTap: () {
                                                  _updateQuantity(item.id, currentQty - 1, availableWarehouseStock);
                                                  setSheetState(() {});
                                                },
                                                child: SizedBox(
                                                  width: 32,
                                                  height: 32,
                                                  child: Icon(
                                                    currentQty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                                    size: 16,
                                                    color: currentQty == 1 ? Colors.red : Colors.teal.shade800,
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () async {
                                                  await _showQuantityDialog(item, currentQty, availableWarehouseStock);
                                                  setSheetState(() {});
                                                },
                                                child: Container(
                                                  constraints: const BoxConstraints(minWidth: 36),
                                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '$currentQty',
                                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                                                onTap: currentQty < availableWarehouseStock
                                                    ? () {
                                                        _updateQuantity(item.id, currentQty + 1, availableWarehouseStock);
                                                        setSheetState(() {});
                                                      }
                                                    : null,
                                                child: SizedBox(
                                                  width: 32,
                                                  height: 32,
                                                  child: Icon(
                                                    Icons.add_rounded,
                                                    size: 16,
                                                    color: currentQty < availableWarehouseStock ? Colors.teal.shade800 : Colors.grey.shade400,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6)),
                                          child: Text('$currentQty loaded', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Amount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Text(
                                Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                              ),
                            ],
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(sheetCtx),
                            child: const Text('Done Reviewing'),
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

  Widget _buildReadOnlyProductCard(InventoryItem item, int currentQty) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isBestSeller = ProductTag.isBestSeller(item.tag);
    final bool isNewProduct = ProductTag.isNewProduct(item.tag);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: currentQty > 0 ? colorScheme.primary.withValues(alpha: 0.05) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: currentQty > 0 ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: currentQty > 0 ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showLoadedSummaryModal(theme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CachedProductImage(imageUrl: item.imageUrl, size: 50),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isBestSeller || isNewProduct) ...[
                          Wrap(
                            spacing: 6,
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
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          item.productName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Text(
                      _currencyFormat.format(item.sellingPrice),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '$currentQty loaded',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManifestEditor(ThemeData theme) {
    final isDraft = _currentVanLoad == null || _currentVanLoad!.status == VanLoadStatus.draft;

    int compareProducts(InventoryItem a, InventoryItem b) {
      return Helperfunctions.compareBySrpAndName(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
      );
    }

    // Filter products by category and search
    final filtered = _allInventoryItems.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.productName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.category.toLowerCase().contains(_searchQuery.toLowerCase());

      bool matchesCategory = true;
      if (_selectedCategory == 'Best Sellers') {
        matchesCategory = item.isSelecta && ProductTag.isBestSeller(item.tag);
      } else if (_selectedCategory == 'By Piece') {
        matchesCategory = item.isSelecta && item.isByPiece;
      } else if (_selectedCategory == 'By Case') {
        matchesCategory = item.isSelecta && item.isByCase;
      } else if (_selectedCategory == 'Other Products') {
        matchesCategory = !item.isSelecta;
      }

      return matchesSearch && matchesCategory;
    }).toList();

    // Build entry list matching book order page catalog structure & sort order
    final entries = <_VanLoadListEntry>[];

    if (_selectedCategory == 'All') {
      final selectaFiltered = filtered.where((i) => i.isSelecta).toList();
      final otherFiltered = filtered.where((i) => !i.isSelecta).toList()..sort(compareProducts);

      final bestSellerProducts = selectaFiltered.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(compareProducts);
      final nonBestSellerSelecta = selectaFiltered.where((i) => !ProductTag.isBestSeller(i.tag)).toList();

      final caseProducts = nonBestSellerSelecta.where((i) => i.isByCase).toList()..sort(compareProducts);
      final pieceProducts = nonBestSellerSelecta.where((i) => !i.isByCase).toList()..sort(compareProducts);

      if (bestSellerProducts.isNotEmpty) {
        entries.add(_VanLoadHeaderEntry(
          title: 'Best Sellers',
          count: bestSellerProducts.length,
          icon: Icons.star_rounded,
          accentColor: const Color(0xFFD97706),
        ));
        for (final item in bestSellerProducts) {
          entries.add(_VanLoadProductEntry(item));
        }
      }

      if (caseProducts.isNotEmpty) {
        entries.add(_VanLoadHeaderEntry(
          title: 'By Case',
          count: caseProducts.length,
          icon: Icons.all_inbox_rounded,
          accentColor: const Color(0xFFEA580C),
        ));
        for (final item in caseProducts) {
          entries.add(_VanLoadProductEntry(item));
        }
      }

      if (pieceProducts.isNotEmpty) {
        entries.add(_VanLoadHeaderEntry(
          title: 'By Piece',
          count: pieceProducts.length,
          icon: Icons.icecream_outlined,
          accentColor: Colors.teal,
        ));
        for (final item in pieceProducts) {
          entries.add(_VanLoadProductEntry(item));
        }
      }

      if (otherFiltered.isNotEmpty) {
        entries.add(_VanLoadHeaderEntry(
          title: 'Other Products',
          count: otherFiltered.length,
          icon: Icons.inventory_2_outlined,
          accentColor: const Color(0xFF475569),
        ));
        for (final item in otherFiltered) {
          entries.add(_VanLoadProductEntry(item));
        }
      }
    } else {
      final sorted = filtered..sort(compareProducts);
      for (final item in sorted) {
        entries.add(_VanLoadProductEntry(item));
      }
    }

    return Column(
      children: [
        // Top info card
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Column(
            children: [
              // Search input
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search product...',
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
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Category filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final cat in ['All', 'Best Sellers', 'By Piece', 'By Case', 'Other Products'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(cat, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: _selectedCategory == cat,
                          selectedColor: Colors.teal.shade100,
                          onSelected: (sel) {
                            if (sel) setState(() => _selectedCategory = cat);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Product list
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'No products found matching filters.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    if (entry is _VanLoadHeaderEntry) {
                      return _buildCategorySectionHeader(
                        title: entry.title,
                        count: entry.count,
                        icon: entry.icon,
                        accentColor: entry.accentColor,
                      );
                    } else if (entry is _VanLoadProductEntry) {
                      final item = entry.item;
                      final currentQty = _loadedQuantities[item.id] ?? 0;
                      final availableWarehouseStock = item.availableQuantity;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: isDraft
                            ? ProductOrderCard(
                                item: item,
                                selectedQty: currentQty,
                                maxOrderable: availableWarehouseStock,
                                isPlaced: false,
                                currencyFormat: _currencyFormat,
                                onTap: () => _showQuantityDialog(item, currentQty, availableWarehouseStock),
                                onIncrement: () {
                                  HapticFeedback.lightImpact();
                                  _updateQuantity(item.id, currentQty + 1, availableWarehouseStock);
                                },
                                onDecrement: () {
                                  HapticFeedback.lightImpact();
                                  _updateQuantity(item.id, currentQty - 1, availableWarehouseStock);
                                },
                              )
                            : _buildReadOnlyProductCard(item, currentQty),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(ThemeData theme) {
    final isDraft = _currentVanLoad == null || _currentVanLoad!.status == VanLoadStatus.draft;
    final loadedSkuCount = _loadedQuantities.values.where((q) => q > 0).length;

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
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _showLoadedSummaryModal(theme),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Colors.teal, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$loadedSkuCount SKU${loadedSkuCount == 1 ? '' : 's'} • $_totalLoadedUnits units',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Colors.teal),
                              ],
                            ),
                            Text(
                              Helperfunctions.formatDoubleAmountForDisplay(_totalLoadedAmount),
                              style: TextStyle(fontSize: 15.5, color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (isDraft && _isDealer)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.local_shipping, size: 18),
                label: const Text('Confirm Load', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                onPressed: _confirmAndDeductWarehouseStock,
              )
            else
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => setState(() => _isCreatingNew = false),
                child: const Text('Close View'),
              ),
          ],
        ),
      ),
    );
  }
}

sealed class _VanLoadListEntry {}

class _VanLoadHeaderEntry extends _VanLoadListEntry {
  final String title;
  final int count;
  final IconData icon;
  final Color accentColor;
  _VanLoadHeaderEntry({
    required this.title,
    required this.count,
    required this.icon,
    required this.accentColor,
  });
}

class _VanLoadProductEntry extends _VanLoadListEntry {
  final InventoryItem item;
  _VanLoadProductEntry(this.item);
}
