import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/delivery_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

/// Presentation view displaying the list of deliveries for a selected date.
///
/// Purely responsible for rendering UI widgets. Data streaming, role checking,
/// summary calculation, date formatting, and filtering are handled by [DeliveryController],
/// while direct database calls are managed in the service layer.
class DeliveryListPage extends StatefulWidget {
  const DeliveryListPage({super.key});

  @override
  State<DeliveryListPage> createState() => _DeliveryListPageState();
}

class _DeliveryListPageState extends State<DeliveryListPage> {
  final DeliveryController _controller = DeliveryController();
  bool isDealer = false;
  int? returnedDeliveryCount;

  DateTime _selectedDate = DateTime.now();
  String _selectedStatusFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    final count = dealer ? await _controller.getCountReturnedDeliveriesOnOtherDays() : 0;
    if (mounted) {
      setState(() {
        isDealer = dealer;
        returnedDeliveryCount = count;
      });
    }
  }

  void onChangeDate() async {
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
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _isEditing = false;
      _editableDeliveryIDs = [];
      _editableDocsById = {};
    });
  }

  String _dateLabel() => _controller.formatDateLabel(_selectedDate);

  void _startEditing(List<QueryDocumentSnapshot<Delivery>> sortedDocs) {
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

  void _resetOrder() {
    final docs = _editableDeliveryIDs
        .map((id) => _editableDocsById[id])
        .whereType<QueryDocumentSnapshot<Delivery>>()
        .toList();
    final defaultSorted = _controller.filterDeliveries(
      docs: docs,
      selectedStatus: 'All',
      searchQuery: '',
      ignoreCustomSequence: true,
    );
    setState(() {
      _editableDeliveryIDs = defaultSorted.map((d) => (d as QueryDocumentSnapshot<Delivery>).id).toList();
      _editableDocsById = {for (final d in defaultSorted) (d as QueryDocumentSnapshot<Delivery>).id: d as QueryDocumentSnapshot<Delivery>};
    });
    ShowMessage.info(context, 'Reset to default delivery sequence. Tap "Save Order" to apply.');
  }

  Future<void> _saveOrder() async {
    if (_editableDeliveryIDs.isEmpty) {
      setState(() => _isEditing = false);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _controller.saveDeliverySequenceOrder(
        orderedDeliveryIDs: _editableDeliveryIDs,
        selectedDate: _selectedDate,
        docsById: _editableDocsById,
      );
      if (!mounted) return;
      ShowMessage.success(context, 'Delivery store order saved successfully!');
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                label: const Text('Today', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
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
      margin: const EdgeInsets.only(top: 8),
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

  Widget _buildInteractiveSummary(List deliveries) {
    final summary = _controller.computeSummaryCounts(deliveries);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(child: _summaryItem('All', summary.all, Theme.of(context).colorScheme.primary, 'All')),
          Expanded(child: _summaryItem('Picklist', summary.pendingPicklist, const Color(0xFF7C3AED), DeliveryStatus.pendingPicklist)),
          Expanded(child: _summaryItem('For Delivery', summary.pending, Colors.orange.shade800, DeliveryStatus.pending)),
          Expanded(child: _summaryItem('Delivered', summary.delivered, Colors.green.shade700, DeliveryStatus.delivered)),
          Expanded(child: _summaryItem('Returned', summary.returned, Colors.red.shade700, DeliveryStatus.returned)),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int count, Color color, String statusKey) {
    final bool isSelected = _selectedStatusFilter == statusKey;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStatusFilter = isSelected && statusKey != 'All' ? 'All' : statusKey;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? color : color.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search stores...',
          hintStyle: TextStyle(fontSize: 15, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          prefixIcon: Icon(Icons.search, size: 22, color: theme.colorScheme.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (Color color, IconData icon, String label) = switch (status) {
      DeliveryStatus.pendingPicklist => (const Color(0xFF7C3AED), Icons.fact_check_outlined, 'Pending Picklist'),
      DeliveryStatus.delivered => (Colors.green.shade700, Icons.check_circle_outline, 'Delivered'),
      DeliveryStatus.returned => (Colors.red.shade700, Icons.cancel_outlined, 'Returned'),
      _ => (Colors.orange.shade800, Icons.local_shipping_outlined, 'For Delivery'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget floatingActionAddButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => BookOrderPage(initialDate: _selectedDate)));
      },
      backgroundColor: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 22),
      label: const Text(
        'Book Order',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppbar(
        title: _isEditing ? 'Rearrange Deliveries' : 'Orders & Deliveries',
        subtitle: _isEditing ? 'Drag to reorder • ${_dateLabel()}' : 'Order → Picklist → Delivery',
        showBackButton: true,
        actions: [
          if (!_isEditing && _currentSortedDocs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
              tooltip: 'Rearrange store order',
              onPressed: () => _startEditing(_currentSortedDocs),
            ),
          if (_isEditing)
            TextButton(
              onPressed: _isSaving ? null : _cancelEditing,
              child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveOrder,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, color: Colors.white, size: 22),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Order',
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              backgroundColor: theme.colorScheme.primary,
            )
          : floatingActionAddButton(),
      body: _isEditing
          ? _buildEditingList()
          : StreamBuilder(
              stream: _controller.getDeliveriesStream(_selectedDate),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load deliveries. Please try again.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const ListSkeleton(itemCount: 6);
                }

                final List allDocs = snapshot.data?.docs ?? [];

                // Filter by status tab & search query via controller
                final filteredDocs = _controller.filterDeliveries(docs: allDocs, selectedStatus: _selectedStatusFilter, searchQuery: _searchQuery);
                _currentSortedDocs = filteredDocs.cast<QueryDocumentSnapshot<Delivery>>();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    children: [
                      _buildDateNavigator(theme),
                      _buildReturnedAlertBanner(),
                      if (allDocs.isNotEmpty) ...[_buildInteractiveSummary(allDocs), _buildSearchBar(theme), const SizedBox(height: 8)],
                      if (filteredDocs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                          child: Row(
                            children: [
                              Icon(Icons.route_outlined, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Arranged by delivery sequence',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                ),
                                onPressed: () => _startEditing(_currentSortedDocs),
                                icon: const Icon(Icons.swap_vert_rounded, size: 16),
                                label: const Text('Edit Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: allDocs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.local_shipping_outlined, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No orders or deliveries for ${DateFormat('d MMM yyyy').format(_selectedDate)}',
                                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          Navigator.push(context, MaterialPageRoute(builder: (context) => BookOrderPage(initialDate: _selectedDate))),
                                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                                      label: const Text('Book Order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              )
                            : filteredDocs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No matching ${_selectedStatusFilter != 'All' ? _selectedStatusFilter : ''} records found',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 80, top: 4),
                                itemCount: filteredDocs.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final Delivery delivery = filteredDocs[index].data();
                                  final String deliveryID = filteredDocs[index].id;
                                  final bool isPendingPicklist = delivery.transactionStatus == DeliveryStatus.pendingPicklist;

                                  return Material(
                                    color: theme.colorScheme.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isPendingPicklist
                                            ? const Color(0xFF7C3AED).withValues(alpha: 0.4)
                                            : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => isPendingPicklist
                                                ? PicklistPage(deliveryID: deliveryID, delivery: delivery)
                                                : DeliveryPage(deliveryID: deliveryID, delivery: delivery),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isPendingPicklist
                                                    ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                                                    : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                isPendingPicklist ? Icons.fact_check_outlined : Icons.storefront_outlined,
                                                color: isPendingPicklist ? const Color(0xFF7C3AED) : theme.colorScheme.primary,
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        margin: const EdgeInsets.only(right: 6),
                                                        decoration: BoxDecoration(
                                                          color: isPendingPicklist
                                                              ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                                                              : theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          '#${index + 1}',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: isPendingPicklist ? const Color(0xFF7C3AED) : theme.colorScheme.onPrimaryContainer,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          delivery.storeName,
                                                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      Text(
                                                        Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w700,
                                                          color: theme.colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                      if (delivery.picklistCompletedDate != null) ...[
                                                        Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant)),
                                                        Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.schedule, size: 13, color: Colors.green.shade700),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              'Picked ${DateFormat('h:mm a').format(delivery.picklistCompletedDate!.toDate())}',
                                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                                                            ),
                                                          ],
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
                                                _statusBadge(delivery.transactionStatus),
                                                const SizedBox(height: 6),
                                                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
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
                  ),
                );
              },
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
            'No orders or deliveries for ${_dateLabel()}.',
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
                  'Drag stores to change delivery order. Top stores will be delivered first.',
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
                onPressed: _resetOrder,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                    color: isTodayPjp
                        ? colorScheme.primary.withValues(alpha: 0.3)
                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                                _statusBadge(delivery.transactionStatus),
                                if (store?.pjpSchedule != null && store!.pjpSchedule!.isNotEmpty)
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
                                          ? 'PJP $targetPjpDay • #${store.pjpSequence != null ? (store.pjpSequence! + 1) : '—'}'
                                          : 'PJP: ${store.pjpSchedule}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isTodayPjp ? Colors.green.shade800 : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                Text(
                                  Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
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
}
