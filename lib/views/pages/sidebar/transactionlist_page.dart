import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/dashboard/delivery_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';
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
  void dispose() {
    dropdownHapiStore.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    dropdownHapiStore.text = widget.storeName;
  }

  Widget _buildFilterCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HapistorePickerField(
            controller: dropdownHapiStore,
            label: 'Select Store',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              segments: const [
                ButtonSegment<String>(
                  value: MonthsAgo.months1,
                  label: Text('This Month', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<String>(
                  value: MonthsAgo.months3,
                  label: Text('3 Months', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment<String>(
                  value: MonthsAgo.months6,
                  label: Text('6 Months', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_selectedMonthsAgo},
              onSelectionChanged: (newSelection) {
                setState(() => _selectedMonthsAgo = newSelection.first);
              },
            ),
          ),
        ],
      ),
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

        double totalAmount = 0;
        for (var doc in allDocs) {
          final delivery = doc.data() as Delivery;
          totalAmount += delivery.orderAmount;
        }

        return Column(
          children: [
            // Lightweight subtitle / summary row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${allDocs.length} ${allDocs.length == 1 ? 'Delivery' : 'Deliveries'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Total: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Clean, focused list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                itemCount: allDocs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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

  Widget _buildTransactionCard({required String deliveryID, required Delivery delivery}) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateStr = delivery.deliveryDate != null
        ? DateFormat('EEE, MMM d, yyyy').format(delivery.deliveryDate!.toDate())
        : 'No date';
    final hasUnpaidCredit = delivery.creditAmount > 0 && delivery.creditStatus == CreditStatus.unpaid;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeliveryPage(deliveryID: deliveryID, delivery: delivery),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (delivery.cashAmount > 0)
                          _buildBadge('Cash: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.cashAmount)}', Colors.green),
                        if (delivery.onlineAmount > 0)
                          _buildBadge('Online: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.onlineAmount)}', Colors.blue),
                        if (delivery.creditAmount > 0)
                          _buildBadge(
                            'Credit: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount)}${hasUnpaidCredit ? ' (Unpaid)' : ''}',
                            hasUnpaidCredit ? Colors.deepOrange : Colors.purple,
                          ),
                        if (delivery.returnAmount > 0)
                          _buildBadge('Return: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.returnAmount)}', Colors.red),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildSelectStorePrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          const Text('Select a store to view transactions', style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, color: colorScheme.outline, size: 44),
            const SizedBox(height: 12),
            const Text('No Delivered Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'No orders found for this timeframe.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 36),
          const SizedBox(height: 8),
          const Text('Unable to load transactions'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Store Transactions',
        subtitle: dropdownHapiStore.text.isNotEmpty ? dropdownHapiStore.text : 'Transaction History',
      ),
      body: Column(
        children: [
          _buildFilterCard(),
          Expanded(child: _buildTransactionStream()),
        ],
      ),
    );
  }
}
