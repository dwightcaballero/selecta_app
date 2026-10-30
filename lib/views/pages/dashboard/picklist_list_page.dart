import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/marked_date_picker.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

class PicklistListPage extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  const PicklistListPage({super.key, this.onOpenDrawer});

  @override
  State<PicklistListPage> createState() => _PicklistListPageState();
}

class _PicklistListPageState extends State<PicklistListPage> {
  final DeliveryController _controller = DeliveryController();
  final TextEditingController _searchController = TextEditingController();
  bool isDealer = false;
  int? returnedDeliveryCount;
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';

  StreamSubscription? _storesSub;
  StreamSubscription<int>? _returnedCountSub;
  StreamSubscription<List<InventoryItem>>? _inventorySub;
  Map<String, Hapistore> _storesByName = {};
  Map<String, String> _storeDocIdsByName = {};
  Map<String, int> _inventoryStockById = {};
  Map<String, int> _inventoryStockByName = {};

  bool _isEditing = false;
  bool _isSaving = false;
  List<String> _editableDeliveryIDs = [];
  Map<String, QueryDocumentSnapshot<Delivery>> _editableDocsById = {};

  String? _selectedDeliveryId;
  Delivery? _selectedDelivery;

  @override
  void initState() {
    super.initState();
    prefetchData();
    _subscribeStores();
    _subscribeInventory();
  }

  @override
  void dispose() {
    _storesSub?.cancel();
    _returnedCountSub?.cancel();
    _inventorySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeStores() {
    _storesSub = HapiStoreService().getListHapiStoresAsStream().listen((snapshot) {
      if (!mounted) return;
      final map = <String, Hapistore>{};
      final docIds = <String, String>{};
      for (final doc in snapshot.docs) {
        final raw = doc.data();
        final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
        final key = store.storeName.trim().toLowerCase();
        map[key] = store;
        docIds[key] = doc.id;
      }
      setState(() {
        _storesByName = map;
        _storeDocIdsByName = docIds;
      });
    });
  }

  void _subscribeInventory() {
    _inventorySub = InventoryService().getActiveInventoryStream().listen((items) {
      if (!mounted) return;
      final byId = <String, int>{};
      final byName = <String, int>{};
      for (final item in items) {
        byId[item.id] = item.stockQuantity;
        final nameKey = item.productName.trim().toLowerCase();
        if (item.stockQuantity > 0 || !byName.containsKey(nameKey)) {
          byName[nameKey] = item.stockQuantity;
        }
      }
      setState(() {
        _inventoryStockById = byId;
        _inventoryStockByName = byName;
      });
    });
  }

  List<({OrderItem item, int requiredQty, int onHandQty})> _getDeliveryShortages(Delivery delivery) {
    final shortages = <({OrderItem item, int requiredQty, int onHandQty})>[];
    for (final item in delivery.items) {
      final reqQty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
      if (reqQty <= 0) continue;
      final nameKey = item.productName.trim().toLowerCase();
      final idStock = _inventoryStockById[item.productId] ?? 0;
      final nameStock = _inventoryStockByName[nameKey] ?? 0;
      final onHand = idStock > nameStock ? idStock : nameStock;
      if (onHand < reqQty) {
        shortages.add((item: item, requiredQty: reqQty, onHandQty: onHand < 0 ? 0 : onHand));
      }
    }
    return shortages;
  }

  Future<void> _onPicklistTileTapped(String deliveryId, Delivery delivery) async {
    final shortages = _getDeliveryShortages(delivery);
    if (shortages.isEmpty) {
      Helperfunctions.navigateTo(context, PicklistPage(deliveryID: deliveryId, delivery: delivery));
      return;
    }

    final hasZeroStock = shortages.any((s) => s.onHandQty <= 0);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasZeroStock ? 'Zero / Insufficient Stock Alert' : 'Stock Shortage Detected',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    delivery.storeName,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  isDealer
                      ? 'The following ${shortages.length} product(s) have zero or insufficient physical stock in the warehouse. You can edit this order now to adjust quantities or update warehouse inventory.'
                      : 'The following ${shortages.length} product(s) have zero or insufficient physical stock in the warehouse. Warehouse pickers cannot pick these items. Please notify the dealer to adjust the picklist or replenish warehouse inventory.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.red.shade900, height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: shortages.length,
                  separatorBuilder: (context, index) => const Divider(height: 12),
                  itemBuilder: (ctx, idx) {
                    final s = shortages[idx];
                    final isZero = s.onHandQty <= 0;
                    return Row(
                      children: [
                        CachedProductImage(imageUrl: s.item.imageUrl, size: 40, borderRadius: 6),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.item.productName,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Category: ${s.item.category.isEmpty ? s.item.productSource : s.item.category}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isZero ? Colors.red.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isZero ? '0 On Hand (Zero Stock)' : 'On Hand: ${s.onHandQty}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isZero ? Colors.red.shade900 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Required: ${s.requiredQty} units',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
          if (isDealer)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Edit Order'),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await Navigator.push<Delivery>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookOrderPage(deliveryID: deliveryId, existingDelivery: delivery, returnUpdatedDeliveryOnSave: true),
                  ),
                );
              },
            ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Helperfunctions.navigateTo(context, PicklistPage(deliveryID: deliveryId, delivery: delivery));
            },
            child: const Text('View Picklist'),
          ),
        ],
      ),
    );
  }

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    if (dealer && _returnedCountSub == null) {
      _returnedCountSub = _controller.getActiveReturnedDeliveriesCountStream().listen((count) {
        if (mounted) setState(() => returnedDeliveryCount = count);
      });
    } else if (!dealer) {
      _returnedCountSub?.cancel();
      _returnedCountSub = null;
    }
    final count = dealer ? await _controller.getCountReturnedDeliveriesOnOtherDays() : 0;
    if (mounted) {
      setState(() {
        isDealer = dealer;
        returnedDeliveryCount = count;
      });
    }
  }

  void onChangeDate() async {
    if (!isDealer) return;
    final dayStatuses = await _controller.getPicklistDayStatuses();
    if (!mounted) return;
    final DateTime? dateTime = await showMarkedDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
      dayStatuses: dayStatuses,
    );

    if (dateTime != null) {
      _searchController.clear();
      setState(() {
        _selectedDate = dateTime;
        _searchQuery = '';
        _isEditing = false;
        _editableDeliveryIDs = [];
        _editableDocsById = {};
      });
    }
  }

  void _changeDate(int days) {
    if (!isDealer) return;
    _searchController.clear();
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _searchQuery = '';
      _isEditing = false;
      _editableDeliveryIDs = [];
      _editableDocsById = {};
    });
  }

  String _dateLabel() => _controller.formatDateLabel(_selectedDate);

  void _startEditing(List<QueryDocumentSnapshot<Delivery>> sortedDocs) {
    if (sortedDocs.length <= 1) return ShowMessage.info(context, 'Nothing to rearrange');
    setState(() {
      _isEditing = true;
      _editableDeliveryIDs = sortedDocs.map((doc) => doc.id).toList();
      _editableDocsById = {for (final doc in sortedDocs) doc.id: doc};
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editableDeliveryIDs = [];
      _editableDocsById = {};
    });
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    setState(() {
      final id = _editableDeliveryIDs.removeAt(oldIndex);
      _editableDeliveryIDs.insert(newIndex, id);
    });
  }

  void _resetToPjpOrder() {
    final docs = _editableDeliveryIDs.map((id) => _editableDocsById[id]).whereType<QueryDocumentSnapshot<Delivery>>().toList();
    final pjpSorted = _controller.sortPendingPicklists(
      docs: docs,
      selectedDate: _selectedDate,
      storesByName: _storesByName,
      ignoreCustomSequence: true,
    );
    setState(() {
      _editableDeliveryIDs = pjpSorted.map((d) => d.id).toList();
      _editableDocsById = {for (final d in pjpSorted) d.id: d};
    });
    final targetPjpDay = _controller.getPreviousPjpDayName(_selectedDate, _storesByName);
    ShowMessage.info(context, 'Reset to $targetPjpDay (Previous Day) PJP schedule order. Tap "Save Order" to apply.');
  }

  Future<void> _saveOrder() async {
    if (_editableDeliveryIDs.isEmpty) {
      setState(() => _isEditing = false);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _controller.savePicklistSequenceOrder(
        orderedDeliveryIDs: _editableDeliveryIDs,
        selectedDate: _selectedDate,
        docsById: _editableDocsById,
        storesByName: _storesByName,
        storeDocIdsByName: _storeDocIdsByName,
      );
      if (!mounted) return;
      ShowMessage.success(context, 'Picklist store order saved successfully!');
      setState(() {
        _isEditing = false;
        _editableDeliveryIDs = [];
        _editableDocsById = {};
      });
    } catch (e) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to save store order: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildDateNavigator(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final bool isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            visualDensity: VisualDensity.compact,
            onPressed: isDealer ? () => _changeDate(-1) : null,
            icon: const Icon(Icons.chevron_left, size: 24),
          ),
          Expanded(
            child: InkWell(
              onTap: isDealer ? onChangeDate : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _dateLabel(),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            visualDensity: VisualDensity.compact,
            onPressed: isDealer ? () => _changeDate(1) : null,
            icon: const Icon(Icons.chevron_right, size: 24),
          ),
          if (isDealer && !isToday) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                label: const Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _selectedDate = DateTime.now()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReturnedAlertBanner() {
    if (!isDealer || returnedDeliveryCount == null || returnedDeliveryCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.red.shade200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (context) => const ReturnlistPage()));
            prefetchData();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.assignment_return_outlined, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$returnedDeliveryCount returned ${returnedDeliveryCount == 1 ? 'delivery needs' : 'deliveries need'} rescheduling',
                    style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.red.shade700, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetPjpDay = _controller.getPreviousPjpDayName(_selectedDate, _storesByName);

    return StreamBuilder<QuerySnapshot<Delivery>>(
      stream: _controller.getPendingPicklistsStream(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];
        final dateDocs = allDocs.where((doc) {
          final delivery = doc.data();
          final dDate = delivery.deliveryDate?.toDate() ?? delivery.createdDate.toDate();
          return DateUtils.isSameDay(dDate, _selectedDate);
        }).toList();

        // Sort based on PJP schedule and order of the current day.
        final allDateSorted = _controller.sortPendingPicklists(docs: dateDocs, selectedDate: _selectedDate, storesByName: _storesByName);

        return Scaffold(
          appBar: CustomAppbar(
            title: _isEditing ? 'Rearrange Picklist' : 'Booked Orders (Picklists)',
            subtitle: _isEditing ? 'Drag to reorder • ${_dateLabel()}' : 'Warehouse Picking • ${_dateLabel()}',
            leading: widget.onOpenDrawer != null && !_isEditing
                ? IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: widget.onOpenDrawer,
                    tooltip: 'Open Menu',
                  )
                : null,
            showBackButton: !_isEditing && widget.onOpenDrawer == null,
            actions: [
              if (!_isEditing)
                IconButton(
                  icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
                  tooltip: 'Rearrange store order',
                  onPressed: () {
                    if (_searchQuery.isNotEmpty) {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    }
                    _startEditing(allDateSorted);
                  },
                ),
              if (_isEditing)
                TextButton(
                  onPressed: _isSaving ? null : _cancelEditing,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          floatingActionButton: _isEditing
              ? FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: _isSaving ? null : _saveOrder,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, color: Colors.white, size: 22),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Order',
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: colorScheme.primary,
                )
              : FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => Helperfunctions.navigateTo(context, BookOrderPage(initialDate: _selectedDate)),
                  icon: const Icon(Icons.storefront_outlined, size: 22),
                  label: const Text('Store Order', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                ),
          body: _isEditing
              ? _buildEditingList()
              : snapshot.hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'Unable to load pending picklists: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                )
              : (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
              ? const ListSkeleton(itemCount: 6)
              : _buildLoadedBody(colorScheme, targetPjpDay, allDateSorted),
        );
      },
    );
  }

  Widget _buildTabletPicklistDetailPreview(
    ColorScheme colorScheme,
    String targetPjpDay,
    Delivery? delivery,
    String? deliveryId,
  ) {
    if (delivery == null || deliveryId == null) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(0, 10, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 52, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'Select an order to view picklist details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'Review line items and stock availability before picking.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      );
    }

    final store = _storesByName[delivery.storeName.trim().toLowerCase()];
    final isTodayPjp = store?.pjpSchedule?.trim().toLowerCase() == targetPjpDay.toLowerCase();
    final shortages = _getDeliveryShortages(delivery);
    final pickedCount = delivery.items.where((i) => i.isPicked).length;
    final totalLines = delivery.items.length;
    final isComplete = totalLines > 0 && pickedCount == totalLines;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(0, 10, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: shortages.isNotEmpty ? Colors.red.shade300 : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isTodayPjp ? colorScheme.primaryContainer.withValues(alpha: 0.6) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.storefront_outlined, color: isTodayPjp ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delivery.storeName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isTodayPjp ? Colors.green.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isTodayPjp
                                  ? 'PJP Stop #${store?.pjpSequence != null ? (store!.pjpSequence! + 1) : 1}'
                                  : (store?.pjpSchedule != null && store!.pjpSchedule!.isNotEmpty
                                      ? 'PJP: ${store.pjpSchedule}'
                                      : 'Not in $targetPjpDay PJP'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isTodayPjp ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                          if (store?.storeContact != null && store!.storeContact.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('•  ${store.storeContact}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isComplete ? Colors.green.withValues(alpha: 0.15) : colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isComplete ? 'Ready ($pickedCount/$totalLines)' : '$pickedCount of $totalLines picked',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isComplete ? Colors.green.shade800 : colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (shortages.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${shortages.length} item(s) have warehouse stock shortage! Review stock before picking.',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryStat(label: 'Line Items', value: '$totalLines', color: colorScheme.onSurface),
                  Container(width: 1, height: 28, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  _buildSummaryStat(
                    label: 'Total Units',
                    value: '${delivery.items.fold<int>(0, (total, i) => total + (i.pickedQuantity > 0 ? i.pickedQuantity : i.orderedQuantity))}',
                    color: Colors.green.shade800,
                  ),
                  Container(width: 1, height: 28, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  _buildSummaryStat(
                    label: 'Picked Units',
                    value: '${delivery.items.where((i) => i.isPicked).fold<int>(0, (total, i) => total + i.pickedQuantity)}',
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Picklist Items ($totalLines)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Expanded(
              child: delivery.items.isEmpty
                  ? Center(child: Text('No items in this picklist', style: TextStyle(color: colorScheme.onSurfaceVariant)))
                  : ListView.separated(
                      primary: false,
                      itemCount: delivery.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = delivery.items[idx];
                        final reqQty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
                        final nameKey = item.productName.trim().toLowerCase();
                        final idStock = _inventoryStockById[item.productId] ?? 0;
                        final nameStock = _inventoryStockByName[nameKey] ?? 0;
                        final onHand = idStock > nameStock ? idStock : nameStock;
                        final isShortage = onHand < reqQty;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              CachedProductImage(imageUrl: item.imageUrl, size: 38, borderRadius: 6),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          '$reqQty units @ ${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice)}',
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                        ),
                                        if (isShortage) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                            child: Text('Stock: $onHand', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    Helperfunctions.formatDoubleAmountForDisplay(item.lineTotal),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  item.isPicked
                                      ? const Icon(Icons.check_circle, size: 16, color: Colors.green)
                                      : Icon(Icons.radio_button_unchecked, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (isDealer) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                    onPressed: () async {
                      await Navigator.push<Delivery>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookOrderPage(deliveryID: deliveryId, existingDelivery: delivery, returnUpdatedDeliveryOnSave: true),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Edit Order'),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _onPicklistTileTapped(deliveryId, delivery),
                    icon: const Icon(Icons.fact_check_rounded, size: 20),
                    label: const Text('Fulfill Picklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedBody(ColorScheme colorScheme, String targetPjpDay, List<QueryDocumentSnapshot<Delivery>> allDateSorted) {
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final filtered = allDateSorted.where((doc) {
      if (_searchQuery.isEmpty) return true;
      return doc.data().storeName.toLowerCase().contains(_searchQuery);
    }).toList();

    if (isTabletLandscape) {
      if (filtered.isNotEmpty) {
        final curIndex = filtered.indexWhere((d) => d.id == _selectedDeliveryId);
        if (curIndex == -1) {
          _selectedDeliveryId = filtered.first.id;
          _selectedDelivery = filtered.first.data();
        } else {
          _selectedDelivery = filtered[curIndex].data();
        }
      } else {
        _selectedDeliveryId = null;
        _selectedDelivery = null;
      }
    }

    final totalOrders = filtered.length;
    final totalUnits = filtered.fold<int>(0, (acc, doc) => acc + doc.data().totalUnits);
    final totalValue = filtered.fold<double>(0.0, (acc, doc) => acc + doc.data().orderAmount);
    final bool isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    final Widget listContent = filtered.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: Icon(Icons.fact_check_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Booked Orders', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No orders matching "$_searchQuery"'
                        : 'All booked orders for ${_dateLabel()} have been picked and moved to Delivery.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.35, color: colorScheme.onSurfaceVariant),
                  ),
                  if (!isToday && _searchQuery.isEmpty) ...[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _selectedDate = DateTime.now();
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.today, size: 18),
                      label: const Text('Go to Today'),
                    ),
                  ] else if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear Search Filter'),
                    ),
                  ],
                ],
              ),
            ),
          )
        : ListView.separated(
            primary: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = filtered[index];
              final deliveryId = doc.id;
              final delivery = doc.data();
              final pickedCount = delivery.items.where((i) => i.isPicked).length;
              final totalLines = delivery.items.length;
              final isComplete = totalLines > 0 && pickedCount == totalLines;
              final shortages = _getDeliveryShortages(delivery);

              final store = _storesByName[delivery.storeName.trim().toLowerCase()];
              final isTodayPjp = store?.pjpSchedule?.trim().toLowerCase() == targetPjpDay.toLowerCase();
              final isSelected = isTabletLandscape && deliveryId == _selectedDeliveryId;

              return Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.25) : colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? colorScheme.primary
                        : (shortages.isNotEmpty
                            ? Colors.red.shade300
                            : (isTodayPjp ? colorScheme.primary.withValues(alpha: 0.25) : colorScheme.outlineVariant.withValues(alpha: 0.55))),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (isTabletLandscape) {
                      setState(() {
                        _selectedDeliveryId = deliveryId;
                        _selectedDelivery = delivery;
                      });
                    } else {
                      _onPicklistTileTapped(deliveryId, delivery);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.15)
                                : (isTodayPjp
                                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#${index + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isTodayPjp || isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                delivery.storeName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.25),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isTodayPjp ? Colors.green.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isTodayPjp
                                          ? 'PJP Stop #${store?.pjpSequence != null ? (store!.pjpSequence! + 1) : (index + 1)}'
                                          : (store?.pjpSchedule != null && store!.pjpSchedule!.isNotEmpty
                                                ? 'PJP: ${store.pjpSchedule}'
                                                : 'Not in $targetPjpDay PJP'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isTodayPjp ? Colors.green.shade800 : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isComplete
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$pickedCount/$totalLines checked',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isComplete ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (shortages.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 11, color: Colors.red.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${shortages.length} shortage${shortages.length > 1 ? 's' : ''}',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

    final Widget listColumn = Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), child: _buildDateNavigator(Theme.of(context))),
        _buildReturnedAlertBanner(),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryStat(label: 'Orders', value: '$totalOrders', color: colorScheme.onSurface),
              Container(width: 1, height: 36, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              _buildSummaryStat(label: 'Total Units', value: '$totalUnits', color: colorScheme.onSurface),
              Container(width: 1, height: 36, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              _buildSummaryStat(label: 'Total Value', value: Helperfunctions.formatDoubleAmountForDisplay(totalValue), color: colorScheme.primary),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Search Hapi Store...',
                hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, size: 22, color: colorScheme.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
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
        Expanded(child: listContent),
      ],
    );

    if (isTabletLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: listColumn),
          const SizedBox(width: 16),
          Expanded(
            flex: 5,
            child: _buildTabletPicklistDetailPreview(colorScheme, targetPjpDay, _selectedDelivery, _selectedDeliveryId),
          ),
        ],
      );
    }

    return listColumn;
  }

  Widget _buildEditingList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final targetPjpDay = _controller.getPreviousPjpDayName(_selectedDate, _storesByName);

    if (_editableDeliveryIDs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No pending picklist orders for ${_dateLabel()}.',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.swap_vert_rounded, size: 22, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Drag stores to change pick order. Top stores will be picked first.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _resetToPjpOrder,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Reset PJP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
            itemCount: _editableDeliveryIDs.length,
            onReorderItem: _onReorderItem,
            itemBuilder: (context, index) {
              final id = _editableDeliveryIDs[index];
              final doc = _editableDocsById[id];
              final delivery = doc?.data();
              if (delivery == null) return SizedBox.shrink(key: ValueKey(id));

              final store = _storesByName[delivery.storeName.trim().toLowerCase()];
              final isTodayPjp = store?.pjpSchedule?.trim().toLowerCase() == targetPjpDay.toLowerCase();

              return Card(
                key: ValueKey(id),
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isTodayPjp ? colorScheme.primary.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isTodayPjp
                              ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isTodayPjp ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              delivery.storeName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isTodayPjp ? Colors.green.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isTodayPjp
                                        ? 'PJP $targetPjpDay • Stop #${store?.pjpSequence != null ? (store!.pjpSequence! + 1) : '—'}'
                                        : (store?.pjpSchedule != null && store!.pjpSchedule!.isNotEmpty
                                              ? 'PJP: ${store.pjpSchedule}'
                                              : 'Not in $targetPjpDay PJP'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isTodayPjp ? Colors.green.shade800 : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                                Text(
                                  Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.drag_handle_rounded, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStat({required String label, required String value, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
