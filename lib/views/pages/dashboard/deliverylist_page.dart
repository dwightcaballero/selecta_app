import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/delivery_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/van_sell_page.dart';
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
  int _selectedSegment = 0; // 0 = Deliveries (Pre-Sell), 1 = Van Sell (Spot)
  String _selectedStatusFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription? _storesSub;
  StreamSubscription<int>? _returnedCountSub;
  late Stream<QuerySnapshot<Delivery>> _deliveriesStream;
  Map<String, Hapistore> _storesByName = {};

  bool _isEditing = false;
  bool _isSaving = false;
  List<String> _editableDeliveryIDs = [];
  Map<String, QueryDocumentSnapshot<Delivery>> _editableDocsById = {};

  @override
  void initState() {
    super.initState();
    _deliveriesStream = _controller.getDeliveriesStream(_selectedDate);
    prefetchData();
    _subscribeStores();
  }

  @override
  void dispose() {
    _storesSub?.cancel();
    _returnedCountSub?.cancel();
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
      });
    });
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
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
        _deliveriesStream = _controller.getDeliveriesStream(_selectedDate);
        _isEditing = false;
        _editableDeliveryIDs = [];
        _editableDocsById = {};
      });
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _deliveriesStream = _controller.getDeliveriesStream(_selectedDate);
      _isEditing = false;
      _editableDeliveryIDs = [];
      _editableDocsById = {};
    });
  }

  String _dateLabel() => _controller.formatDateLabel(_selectedDate);

  void _startEditing(List<QueryDocumentSnapshot<Delivery>> docs) {
    final preSellDocs = docs.where((doc) => !doc.data().isVanSell).toList();
    final sorted = _controller.filterDeliveries(docs: preSellDocs, selectedStatus: 'All', searchQuery: '', isVanSellOnly: false);
    setState(() {
      _isEditing = true;
      _searchQuery = '';
      _searchController.clear();
      _selectedStatusFilter = 'All';
      _editableDeliveryIDs = sorted.map((doc) => (doc as QueryDocumentSnapshot<Delivery>).id).toList();
      _editableDocsById = {for (final doc in sorted) (doc as QueryDocumentSnapshot<Delivery>).id: doc};
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

  void _resetOrder() {
    final docs = _editableDeliveryIDs.map((id) => _editableDocsById[id]).whereType<QueryDocumentSnapshot<Delivery>>().toList();
    final defaultSorted = _controller.filterDeliveries(
      docs: docs,
      selectedStatus: 'All',
      searchQuery: '',
      ignoreCustomSequence: true,
      isVanSellOnly: false,
    );
    setState(() {
      _editableDeliveryIDs = defaultSorted.map((d) => (d as QueryDocumentSnapshot<Delivery>).id).toList();
      _editableDocsById = {for (final d in defaultSorted) (d as QueryDocumentSnapshot<Delivery>).id: d};
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
      await _controller.saveDeliverySequenceOrder(orderedDeliveryIDs: _editableDeliveryIDs, selectedDate: _selectedDate, docsById: _editableDocsById);
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
      margin: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _buildSummaryStat({required String label, required String value, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSegmentedHeader(ThemeData theme, DeliverySummaryCounts summary) {
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                if (_selectedSegment != 0) {
                  setState(() {
                    _selectedSegment = 0;
                    _selectedStatusFilter = 'All';
                  });
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedSegment == 0 ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedSegment == 0
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_shipping_outlined, size: 18, color: _selectedSegment == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Text(
                      'Deliveries (${summary.all})',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: _selectedSegment == 0 ? FontWeight.bold : FontWeight.w600,
                        color: _selectedSegment == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () {
                if (_selectedSegment != 1) {
                  setState(() {
                    _selectedSegment = 1;
                    _selectedStatusFilter = 'All';
                  });
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedSegment == 1 ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedSegment == 1
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_car_filled_outlined, size: 18, color: _selectedSegment == 1 ? Colors.teal : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Text(
                      'Van Sell (${summary.vanSellCount})',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: _selectedSegment == 1 ? FontWeight.bold : FontWeight.w600,
                        color: _selectedSegment == 1 ? Colors.teal : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreSellSummaryBar(DeliverySummaryCounts summary) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryStat(label: 'Deliveries', value: '${summary.all}', color: colorScheme.onSurface),
          Container(width: 1, height: 32, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          _buildSummaryStat(label: 'Pending', value: '${summary.pending}', color: Colors.orange.shade800),
          Container(width: 1, height: 32, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          _buildSummaryStat(
            label: 'Expected Total',
            value: Helperfunctions.formatDoubleAmountForDisplay(summary.totalExpectedAmount),
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildVanSellSummaryBar(DeliverySummaryCounts summary) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryStat(label: 'Van Sells', value: '${summary.vanSellCount}', color: Colors.teal.shade800),
          Container(width: 1, height: 32, color: Colors.teal.withValues(alpha: 0.2)),
          _buildSummaryStat(
            label: 'Total Revenue',
            value: Helperfunctions.formatDoubleAmountForDisplay(summary.vanSellAmount),
            color: Colors.teal.shade900,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final hint = _selectedSegment == 1 ? 'Search Van Sell store or receipt...' : 'Search Hapi Store...';

    return SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 22, color: _selectedSegment == 1 ? Colors.teal : colorScheme.primary),
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
    );
  }

  Widget _statusBadge(String status) {
    final (Color color, IconData icon, String label) = switch (status) {
      DeliveryStatus.pendingPicklist => (const Color(0xFF7C3AED), Icons.fact_check_outlined, 'Booked'),
      DeliveryStatus.delivered => (Colors.green.shade700, Icons.check_circle_outline, 'Delivered'),
      DeliveryStatus.returned => (Colors.red.shade700, Icons.cancel_outlined, 'Returned'),
      DeliveryStatus.voided => (Colors.grey.shade600, Icons.block_outlined, 'Voided'),
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

  Widget _buildVanSellCard({required BuildContext context, required Delivery delivery, required String deliveryID, required int index}) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeStr = DateFormat('h:mm a').format(delivery.createdDate.toDate());

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
            ),
          );
          prefetchData();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.point_of_sale_rounded, color: Colors.teal, size: 24),
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
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            delivery.storeName.isEmpty ? 'Direct / Walk-in Buyer' : delivery.storeName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                        if (delivery.items.isNotEmpty)
                          Text(
                            '•  ${delivery.items.length} ${delivery.items.length == 1 ? "item" : "items"}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                          ),
                        if (delivery.cashAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Cash: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.cashAmount)}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                            ),
                          ),
                        if (delivery.onlineAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Online: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.onlineAmount)}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                            ),
                          ),
                        if (delivery.creditAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Credit: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount)}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                            ),
                          ),
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
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget floatingActionButton() {
    if (_selectedSegment == 1) {
      return FloatingActionButton.extended(
        heroTag: 'van_sell_add_btn',
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => const VanSellPage()));
          prefetchData();
        },
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white, size: 22),
        label: const Text(
          'New Van Sell',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );
    }

    return FloatingActionButton.extended(
      heroTag: 'store_order_add_btn',
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => BookOrderPage(initialDate: _selectedDate)));
      },
      backgroundColor: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
      label: const Text(
        'Store Order',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot<Delivery>>(
      stream: _deliveriesStream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<Delivery>> snapshot) {
        final List<QueryDocumentSnapshot<Delivery>> allDocs = (snapshot.data?.docs ?? []).where((doc) {
          final delivery = doc.data();
          return delivery.transactionStatus != DeliveryStatus.pendingPicklist && delivery.transactionStatus != DeliveryStatus.voided;
        }).toList();

        final summary = _controller.computeSummaryCounts(allDocs);
        final bool isVanSell = _selectedSegment == 1;

        final preSellDocs = allDocs.where((d) => !d.data().isVanSell).toList();
        final vanSellDocs = allDocs.where((d) => d.data().isVanSell).toList();

        final filteredDocs = _controller.filterDeliveries(
          docs: allDocs,
          selectedStatus: _selectedStatusFilter,
          searchQuery: _searchQuery,
          isVanSellOnly: isVanSell,
        );

        return Scaffold(
          appBar: CustomAppbar(
            title: _isEditing ? 'Rearrange Deliveries' : (isVanSell ? 'Van Sell Transactions' : 'Orders & Deliveries'),
            subtitle: _isEditing
                ? 'Drag to reorder • ${_dateLabel()}'
                : (isVanSell ? 'Spot sales off truck • ${_dateLabel()}' : 'Order → Picklist → Delivery'),
            showBackButton: true,
            actions: [
              if (!_isEditing && !isVanSell && preSellDocs.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.swap_vert_rounded, color: Colors.white),
                  tooltip: 'Rearrange store order',
                  onPressed: () => _startEditing(preSellDocs),
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
                  backgroundColor: theme.colorScheme.primary,
                )
              : floatingActionButton(),
          body: _isEditing
              ? _buildEditingList()
              : snapshot.hasError
              ? const Center(child: Text('Unable to load deliveries. Please try again.'))
              : (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
              ? const ListSkeleton(itemCount: 6)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    children: [
                      _buildDateNavigator(theme),
                      _buildReturnedAlertBanner(),
                      _buildSegmentedHeader(theme, summary),
                      if (!isVanSell) ...[_buildPreSellSummaryBar(summary)] else ...[_buildVanSellSummaryBar(summary)],
                      const SizedBox(height: 6),
                      _buildSearchBar(theme),
                      const SizedBox(height: 6),
                      Expanded(
                        child: !isVanSell
                            ? (preSellDocs.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.local_shipping_outlined, size: 48, color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No scheduled deliveries for ${DateFormat('d MMM yyyy').format(_selectedDate)}',
                                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => BookOrderPage(initialDate: _selectedDate)),
                                            ),
                                            icon: const Icon(Icons.storefront_outlined, size: 20),
                                            label: const Text('Store Order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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

                                        return Material(
                                          color: theme.colorScheme.surface,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                          ),
                                          child: InkWell(
                                            onTap: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
                                                ),
                                              );
                                              prefetchData();
                                            },
                                            borderRadius: BorderRadius.circular(12),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Icon(Icons.storefront_outlined, color: theme.colorScheme.primary, size: 24),
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
                                                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                '#${index + 1}',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: theme.colorScheme.onPrimaryContainer,
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
                                                          spacing: 6,
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
                                                            if (delivery.hasReturnedItems || delivery.returnAmount > 0)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.red.withValues(alpha: 0.1),
                                                                  borderRadius: BorderRadius.circular(6),
                                                                ),
                                                                child: Text(
                                                                  '${Helperfunctions.formatDoubleAmountForDisplay(delivery.returnAmount)} ret.',
                                                                  style: TextStyle(
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: Colors.red.shade800,
                                                                  ),
                                                                ),
                                                              ),
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
                                    ))
                            : (vanSellDocs.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.directions_car_filled_outlined, size: 48, color: Colors.teal.shade300),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No Van Sell transactions for ${DateFormat('d MMM yyyy').format(_selectedDate)}',
                                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Sell directly to stores off your van load stock.',
                                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton.icon(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                                            onPressed: () async {
                                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const VanSellPage()));
                                              prefetchData();
                                            },
                                            icon: const Icon(Icons.add, size: 20),
                                            label: const Text('New Van Sell', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                          const Text(
                                            'No matching van sell records found',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
                                        return _buildVanSellCard(context: context, delivery: delivery, deliveryID: deliveryID, index: index);
                                      },
                                    )),
                      ),
                    ],
                  ),
                ),
        );
      },
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
                                if (delivery.isVanSell)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.teal.withValues(alpha: 0.4), width: 1),
                                    ),
                                    child: const Text(
                                      'VAN SELL',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.teal),
                                    ),
                                  ),
                                _statusBadge(delivery.transactionStatus),
                                if (store?.pjpSchedule != null && store!.pjpSchedule!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isTodayPjp ? Colors.green.withValues(alpha: 0.12) : Colors.amber.withValues(alpha: 0.15),
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
}
