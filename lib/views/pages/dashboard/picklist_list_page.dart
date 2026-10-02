import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
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
    isDealer = await _controller.checkIsDealer();
    if (mounted) setState(() {});
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
      });
    }
  }

  void _changeDate(int days) {
    if (!isDealer) return;
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

    return Scaffold(
      appBar: const CustomAppbar(title: 'Pending Picklists'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Helperfunctions.navigateTo(context, BookOrderPage(initialDate: _selectedDate)),
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 22),
        label: const Text('Book Order', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
      ),
      body: Column(
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

                final totalOrders = filtered.length;
                final totalUnits = filtered.fold<int>(0, (acc, doc) => acc + doc.data().totalUnits);
                final totalValue = filtered.fold<double>(0.0, (acc, doc) => acc + doc.data().orderAmount);

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
                    const SizedBox(height: 4),
                    Expanded(
                      child: filtered.isEmpty
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
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = filtered[index];
                                final deliveryId = doc.id;
                                final delivery = doc.data();
                                final pickedCount = delivery.items.where((i) => i.isPicked).length;
                                final totalLines = delivery.items.length;
                                final isComplete = totalLines > 0 && pickedCount == totalLines;
                                final deliveryDate = delivery.deliveryDate?.toDate() ?? DateTime.now();

                                return Card(
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  color: colorScheme.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => Helperfunctions.navigateTo(context, PicklistPage(deliveryID: deliveryId, delivery: delivery)),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(11),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(Icons.storefront_outlined, color: colorScheme.onSurfaceVariant, size: 24),
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
                                                const SizedBox(height: 3),
                                                Text(
                                                  Helperfunctions.formatDateForDisplay(deliveryDate),
                                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
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
