import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

class PicklistListPage extends StatefulWidget {
  const PicklistListPage({super.key});

  @override
  State<PicklistListPage> createState() => _PicklistListPageState();
}

class _PicklistListPageState extends State<PicklistListPage> {
  final DeliveryController _controller = DeliveryController();
  final TextEditingController _searchController = TextEditingController();
  bool isDealer = false;
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';

  StreamSubscription? _storesSub;
  Map<String, Hapistore> _storesByName = {};
  Map<String, String> _storeDocIdsByName = {};

  bool _isEditing = false;
  bool _isSaving = false;
  List<String> _editableDeliveryIDs = [];
  Map<String, QueryDocumentSnapshot<Delivery>> _editableDocsById = {};
  List<QueryDocumentSnapshot<Delivery>> _currentSortedDocs = [];

  @override
  void initState() {
    super.initState();
    prefetchData();
    _subscribeStores();
  }

  @override
  void dispose() {
    _storesSub?.cancel();
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

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        isDealer = dealer;
      });
    }
  }

  void onChangeDate() async {
    if (!isDealer) return;
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
        _isEditing = false;
        _editableDeliveryIDs = [];
        _editableDocsById = {};
      });
    }
  }

  void _changeDate(int days) {
    if (!isDealer) return;
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetPjpDay = _controller.getPreviousPjpDayName(_selectedDate, _storesByName);

    return Scaffold(
      appBar: CustomAppbar(
        title: _isEditing ? 'Rearrange Picklist' : 'Pending Picklists',
        subtitle: _isEditing ? 'Drag to reorder • ${_dateLabel()}' : null,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
              tooltip: 'Rearrange store order',
              onPressed: () => _startEditing(_currentSortedDocs),
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
          : Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 4), child: _buildDateNavigator(Theme.of(context))),
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
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Delivery>>(
                    stream: _controller.getPendingPicklistsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'Unable to load pending picklists: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const ListSkeleton(itemCount: 6);
                      }

                      final allDocs = snapshot.data?.docs ?? [];
                      final filtered = allDocs.where((doc) {
                        final delivery = doc.data();
                        final dDate = delivery.deliveryDate?.toDate() ?? delivery.createdDate.toDate();
                        if (!DateUtils.isSameDay(dDate, _selectedDate)) {
                          return false;
                        }
                        if (_searchQuery.isEmpty) return true;
                        return delivery.storeName.toLowerCase().contains(_searchQuery);
                      }).toList();

                      // Sort based on PJP schedule and order of the current day.
                      // Stores not part of today's PJP schedule are placed at the bottom.
                      final sorted = _controller.sortPendingPicklists(docs: filtered, selectedDate: _selectedDate, storesByName: _storesByName);
                      _currentSortedDocs = sorted;

                      final totalOrders = sorted.length;
                      final totalUnits = sorted.fold<int>(0, (acc, doc) => acc + doc.data().totalUnits);
                      final totalValue = sorted.fold<double>(0.0, (acc, doc) => acc + doc.data().orderAmount);

                      return Column(
                        children: [
                          // Clean neutral summary bar
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
                                _buildSummaryStat(
                                  label: 'Total Value',
                                  value: Helperfunctions.formatDoubleAmountForDisplay(totalValue),
                                  color: colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: sorted.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(18),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.fact_check_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text('No Pending Picklists', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 8),
                                          Text(
                                            _searchQuery.isNotEmpty
                                                ? 'No orders matching "$_searchQuery"'
                                                : 'All booked orders for ${_dateLabel()} have been picked and moved to Delivery.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(fontSize: 13.5, height: 1.35, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                                    itemCount: sorted.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final doc = sorted[index];
                                      final deliveryId = doc.id;
                                      final delivery = doc.data();
                                      final pickedCount = delivery.items.where((i) => i.isPicked).length;
                                      final totalLines = delivery.items.length;
                                      final isComplete = totalLines > 0 && pickedCount == totalLines;
                                      final deliveryDate = delivery.deliveryDate?.toDate() ?? DateTime.now();

                                      final store = _storesByName[delivery.storeName.trim().toLowerCase()];
                                      final isTodayPjp = store?.pjpSchedule?.trim().toLowerCase() == targetPjpDay.toLowerCase();

                                      return Card(
                                        elevation: 0,
                                        margin: EdgeInsets.zero,
                                        color: colorScheme.surface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: isTodayPjp
                                                ? colorScheme.primary.withValues(alpha: 0.25)
                                                : colorScheme.outlineVariant.withValues(alpha: 0.55),
                                          ),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => Helperfunctions.navigateTo(context, PicklistPage(deliveryID: deliveryId, delivery: delivery)),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: isTodayPjp
                                                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                                                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(
                                                    '#${index + 1}',
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
                                                              color: isTodayPjp
                                                                  ? Colors.green.withValues(alpha: 0.12)
                                                                  : Colors.amber.withValues(alpha: 0.15),
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
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              Helperfunctions.formatDateForDisplay(deliveryDate),
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w500,
                                                                color: colorScheme.onSurfaceVariant,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
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
                                                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                                        borderRadius: BorderRadius.circular(8),
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
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
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
