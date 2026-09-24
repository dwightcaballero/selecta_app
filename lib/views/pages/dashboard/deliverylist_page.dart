import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/dashboard/delivery_page.dart';
import 'package:flutter_app/views/pages/dashboard/returnlist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class DeliveryListPage extends StatefulWidget {
  const DeliveryListPage({super.key});

  @override
  State<DeliveryListPage> createState() => _DeliveryListPageState();
}

class _DeliveryListPageState extends State<DeliveryListPage> {
  final DeliveryService db = DeliveryService();
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
    isDealer = await KVariables.getIsDealer();
    returnedDeliveryCount = await DeliveryService.getCountReturnedDeliveriesOnOtherDays();
    if (mounted) setState(() {});
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

  String _dateLabel() {
    final today = DateTime.now();
    final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);

    if (selectedDay == currentDay) return 'Today, ${DateFormat('d MMM yyyy').format(_selectedDate)}';
    if (selectedDay == currentDay.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('d MMM').format(_selectedDate)}';
    }
    if (selectedDay == currentDay.add(const Duration(days: 1))) {
      return 'Tomorrow, ${DateFormat('d MMM').format(_selectedDate)}';
    }
    return DateFormat('EEE, d MMM yyyy').format(_selectedDate);
  }

  Widget _buildDateNavigator(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final bool isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
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
            icon: const Icon(Icons.chevron_left, size: 22),
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
                    Icon(Icons.calendar_today_outlined, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _dateLabel(),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
          if (isDealer && !isToday) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: const Text('Today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _selectedDate = DateTime.now()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReturnedAlertBanner() {
    if (returnedDeliveryCount == null || returnedDeliveryCount == 0) {
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.assignment_return_outlined, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$returnedDeliveryCount returned ${returnedDeliveryCount == 1 ? 'delivery needs' : 'deliveries need'} rescheduling',
                    style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.red.shade700, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveSummary(List deliveries) {
    int pending = 0;
    int delivered = 0;
    int returned = 0;

    for (final item in deliveries) {
      final status = (item.data() as Delivery).transactionStatus;
      if (status == DeliveryStatus.pending) pending++;
      if (status == DeliveryStatus.delivered) delivered++;
      if (status == DeliveryStatus.returned) returned++;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(child: _summaryItem('All', deliveries.length, Theme.of(context).colorScheme.primary, 'All')),
          Expanded(child: _summaryItem('Delivered', delivered, Colors.green.shade700, DeliveryStatus.delivered)),
          Expanded(child: _summaryItem('Pending', pending, Colors.orange.shade800, DeliveryStatus.pending)),
          Expanded(child: _summaryItem('Returned', returned, Colors.red.shade700, DeliveryStatus.returned)),
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : color.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search stores...',
          hintStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
    final (Color color, IconData icon) = switch (status) {
      DeliveryStatus.delivered => (Colors.green.shade700, Icons.check_circle_outline),
      DeliveryStatus.returned => (Colors.red.shade700, Icons.cancel_outlined),
      _ => (Colors.orange.shade800, Icons.pending_actions),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget floatingActionAddButton() {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeliveryPage(deliveryID: '', delivery: Delivery.empty()),
          ),
        );
      },
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const CustomAppbar(title: 'Delivery', subtitle: 'List of Deliveries', showBackButton: true),
      floatingActionButton: isDealer ? floatingActionAddButton() : null,
      body: StreamBuilder(
        stream: db.getListDeliveryByDate(_selectedDate),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load deliveries. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final List allDocs = snapshot.data?.docs ?? [];

          // Filter by status tab & search query
          final filteredDocs = allDocs.where((doc) {
            final Delivery delivery = doc.data();
            final matchesStatus = _selectedStatusFilter == 'All' || delivery.transactionStatus == _selectedStatusFilter;
            final matchesSearch = _searchQuery.isEmpty || delivery.storeName.toLowerCase().contains(_searchQuery.toLowerCase());
            return matchesStatus && matchesSearch;
          }).toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              children: [
                _buildDateNavigator(theme),
                _buildReturnedAlertBanner(),
                if (allDocs.isNotEmpty) ...[
                  _buildInteractiveSummary(allDocs),
                  _buildSearchBar(theme),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: allDocs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_shipping_outlined, size: 44, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('No deliveries for ${DateFormat('d MMM yyyy').format(_selectedDate)}'),
                              if (isDealer) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DeliveryPage(deliveryID: '', delivery: Delivery.empty()),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add delivery'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : filteredDocs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off, size: 36, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text('No matching ${_selectedStatusFilter != 'All' ? _selectedStatusFilter : ''} deliveries found'),
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
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(Icons.storefront_outlined, color: theme.colorScheme.primary, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  delivery.storeName,
                                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
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
                                              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
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
