import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/delivery_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({super.key, required this.storeName});
  final String storeName;

  @override
  State<TransactionListPage> createState() => _TransactionListPageState();
}

class _TransactionListPageState extends State<TransactionListPage> {
  final DeliveryService db = DeliveryService();
  final HapiStoreService dbHS = HapiStoreService();
  final TextEditingController dropdownHapiStore = TextEditingController();
  String _selectedMonthsAgo = MonthsAgo.months1;

  @override
  void initState() {
    super.initState();
    dropdownHapiStore.text = widget.storeName;
  }

  @override
  void dispose() {
    dropdownHapiStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Store Transactions', subtitle: dropdownHapiStore.text.isNotEmpty ? dropdownHapiStore.text : 'Transaction History'),
      body: Column(
        children: [
          // 1. Store Selector & Timeframe Filter Card
          _buildFilterCard(),

          // 2. Transaction Stream List with Summary
          Expanded(child: _buildTransactionStream()),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          // Store Dropdown
          _buildHapistoreDropdown(),

          // Time Range Segmented Control
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Time Range',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  segments: const [
                    ButtonSegment<String>(
                      value: MonthsAgo.months1,
                      label: Text('Past Month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      icon: Icon(Icons.calendar_today_outlined, size: 16),
                    ),
                    ButtonSegment<String>(
                      value: MonthsAgo.months3,
                      label: Text('3 Months', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      icon: Icon(Icons.date_range_outlined, size: 16),
                    ),
                    ButtonSegment<String>(
                      value: MonthsAgo.months6,
                      label: Text('6 Months', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      icon: Icon(Icons.history_outlined, size: 16),
                    ),
                  ],
                  selected: {_selectedMonthsAgo},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedMonthsAgo = newSelection.first;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHapistoreDropdown() {
    return StreamBuilder(
      stream: dbHS.getListHapiStoresAsStream(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final listHapiStore = snapshot.data?.docs ?? [];
        List<DropdownMenuEntry<String>> listDropdownItems = [];
        for (int i = 0; i < listHapiStore.length; i++) {
          Hapistore hapistore = listHapiStore[i].data();
          listDropdownItems.add(DropdownMenuEntry(value: hapistore.storeName, label: hapistore.storeName));
        }

        return DropdownMenuFormField<String>(
          controller: dropdownHapiStore,
          initialSelection: dropdownHapiStore.text,
          label: const Text('Select Store'),
          leadingIcon: const Icon(Icons.storefront_outlined, size: 20),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          dropdownMenuEntries: listDropdownItems,
          enableSearch: true,
          enableFilter: true,
          requestFocusOnTap: true,
          expandedInsets: EdgeInsets.zero,
          menuHeight: 300,
          onSelected: (_) => setState(() {}),
        );
      },
    );
  }

  Widget _buildTransactionStream() {
    if (dropdownHapiStore.text.isEmpty) {
      return _buildSelectStorePrompt();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: db.getListDeliveryByStoreNameAndDateRange(dropdownHapiStore.text, _selectedMonthsAgo),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return _buildEmptyState();
        }

        double totalPeriodAmount = 0;
        for (var doc in allDocs) {
          final delivery = doc.data() as Delivery;
          totalPeriodAmount += delivery.orderAmount;
        }

        return Column(
          children: [
            // KPI Summary Header
            _buildSummaryBanner(totalAmount: totalPeriodAmount, totalCount: allDocs.length),

            // Transactions List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: allDocs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final delivery = allDocs[index].data() as Delivery;
                  final deliveryID = allDocs[index].id;
                  return _buildTransactionCard(deliveryID: deliveryID, delivery: delivery);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryBanner({required double totalAmount, required int totalCount}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Delivered Revenue', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(
              '$totalCount Deliveries',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard({required String deliveryID, required Delivery delivery}) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr = delivery.deliveryDate != null ? DateFormat('EEEE, d MMMM yyyy').format(delivery.deliveryDate!.toDate()) : 'No date';

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                  ),
                ],
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      if (delivery.cashAmount > 0)
                        _buildPaymentBadge('Cash: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.cashAmount)}', Colors.green),
                      if (delivery.onlineAmount > 0)
                        _buildPaymentBadge('Online: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.onlineAmount)}', Colors.blue),
                      if (delivery.creditAmount > 0)
                        _buildPaymentBadge('Credit: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount)}', Colors.purple),
                      if (delivery.returnAmount > 0)
                        _buildPaymentBadge('Return: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.returnAmount)}', Colors.red),
                    ],
                  ),
                  Icon(Icons.chevron_right, size: 18, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildSelectStorePrompt() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Select a Hapi Store to view transactions', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_outlined, color: Colors.blue, size: 50),
            ),
            const SizedBox(height: 16),
            const Text('No Delivered Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'No delivered orders found for "${dropdownHapiStore.text}" within the selected timeframe.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          SizedBox(height: 8),
          Text('Unable to load transaction list'),
        ],
      ),
    );
  }
}
