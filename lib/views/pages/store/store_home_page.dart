import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/store/store_cart_page.dart';
import 'package:selecta_ops/views/pages/store/store_order_detail_page.dart';
import 'package:selecta_ops/views/pages/store/store_performance_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Store Home Landing Page.
/// Welcomes store owner, shows active orders status, next scheduled delivery date,
/// and provides 1-click reorder and fast navigation to catalog.
class StoreHomePage extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const StoreHomePage({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFormat = DateFormat('EEE, MMM d, yyyy');

  Future<void> _quickReorder(StoreOrder order) async {
    try {
      final catalog = await SelectaProductService().getAllSelectaProductList();
      StoreCartController().loadFromStoreOrder(order, catalog);

      if (mounted) {
        ShowMessage.success(context, 'Items from order #${order.orderNumber} loaded into cart!');
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StoreCartPage()),
        );
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Unable to load products: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;
        final storeName = user.storeName;
        final dealerName = user.dealerName;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Store Portal'),
            actions: [
              IconButton(
                icon: const Icon(Icons.analytics_outlined),
                tooltip: 'Store Analytics',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StorePerformancePage()),
                  );
                },
              ),
            ],
          ),
          body: StreamBuilder<DocumentSnapshot>(
            stream: storeId.isNotEmpty
                ? FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).doc(storeId).snapshots()
                : const Stream.empty(),
            builder: (context, storeDocSnapshot) {
              final storeData = storeDocSnapshot.data?.data() as Map<String, dynamic>?;
              final isOrderingEnabled = storeData?['orderingEnabled'] as bool? ?? true;

              return StreamBuilder<QuerySnapshot>(
                stream: storeId.isNotEmpty
                    ? FirebaseFirestore.instance
                        .collection('store_orders')
                        .where('storeId', isEqualTo: storeId)
                        .orderBy('createdAt', descending: true)
                        .snapshots()
                    : const Stream.empty(),
                builder: (context, ordersSnapshot) {
                  final orderDocs = ordersSnapshot.data?.docs ?? [];
                  final orders = orderDocs.map((d) => StoreOrder.fromJson(d.data() as Map<String, dynamic>, id: d.id)).toList();

                  // Find open orders
                  final openOrders = orders.where((o) =>
                      o.status == StoreOrderStatus.submitted ||
                      o.status == StoreOrderStatus.approved ||
                      o.status == StoreOrderStatus.outForDelivery).toList();

                  // Find next delivery date
                  DateTime? nextDelivery;
                  for (final o in openOrders) {
                    final dDate = o.deliveryDate?.toDate();
                    if (dDate != null) {
                      if (nextDelivery == null || dDate.isBefore(nextDelivery)) {
                        nextDelivery = dDate;
                      }
                    }
                  }

                  final lastOrder = orders.isNotEmpty ? orders.first : null;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Ordering Disabled Warning Banner
                        if (!isOrderingEnabled) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.pause_circle_outline_rounded, color: Colors.orange, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Ordering Temporarily Paused', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                      SizedBox(height: 2),
                                      Text(
                                        'Self-ordering is paused for this store. Please contact your dealer for assistance.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Welcome Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.storefront_rounded, size: 28, color: colorScheme.primary),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            storeName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Dealer: $dealerName',
                                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: isOrderingEnabled
                                      ? () => widget.onNavigateToTab?.call(1)
                                      : null,
                                  icon: const Icon(Icons.add_shopping_cart_rounded),
                                  label: const Text('Start New Order', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Active Orders Summary Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Open Orders', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (openOrders.isNotEmpty ? Colors.blue : Colors.grey)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${openOrders.length} In Progress',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: openOrders.isNotEmpty ? Colors.blue : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (nextDelivery != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.local_shipping_rounded, color: Colors.green, size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Next Scheduled Delivery',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                              ),
                                              Text(
                                                _dateFormat.format(nextDelivery),
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextButton.icon(
                                  onPressed: () => widget.onNavigateToTab?.call(2),
                                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                                  label: const Text('View All Orders'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Last Order Card with 1-Click Reorder
                        if (lastOrder != null) ...[
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Most Recent Order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                      Text(
                                        '#${lastOrder.orderNumber}',
                                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${lastOrder.items.length} items • ${_currency.format(lastOrder.approvedTotal ?? lastOrder.estimatedTotal)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Placed ${_dateFormat.format(lastOrder.createdAt.toDate())}',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => StoreOrderDetailPage(order: lastOrder)),
                                            );
                                          },
                                          icon: const Icon(Icons.visibility_outlined, size: 16),
                                          label: const Text('Details'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: isOrderingEnabled ? () => _quickReorder(lastOrder) : null,
                                          icon: const Icon(Icons.replay_rounded, size: 16),
                                          label: const Text('Reorder'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
