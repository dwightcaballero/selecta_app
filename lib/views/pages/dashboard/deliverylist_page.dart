import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/delivery_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    final count = dealer
        ? await _controller.getCountReturnedDeliveriesOnOtherDays()
        : 0;
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
      });
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  String _dateLabel() => _controller.formatDateLabel(_selectedDate);

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
      appBar: const CustomAppbar(title: 'Orders & Deliveries', subtitle: 'Order → Picklist → Delivery', showBackButton: true),
      floatingActionButton: floatingActionAddButton(),
      body: StreamBuilder(
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

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              children: [
                _buildDateNavigator(theme),
                _buildReturnedAlertBanner(),
                if (allDocs.isNotEmpty) ...[_buildInteractiveSummary(allDocs), _buildSearchBar(theme), const SizedBox(height: 8)],
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
                                            Text(delivery.storeName, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
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
}
