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
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;
        final storeName = user.storeName.isNotEmpty ? user.storeName : 'Hapi Store';
        final dealerName = user.dealerName.isNotEmpty ? user.dealerName : 'Selecta Dealer';
        final username = user.username;

        return Scaffold(
          appBar: CustomAppbar(
            title: 'Store Portal',
            subtitle: 'Selecta Self-Ordering',
            showBackButton: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.analytics_outlined, color: Colors.white),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Ordering Disabled Warning Banner
                        if (!isOrderingEnabled) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF332200) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFFDE68A),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.pause_circle_outline_rounded, color: Color(0xFFD97706), size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ordering Temporarily Paused',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Self-ordering is currently paused for this store. Please contact your dealer for assistance.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF78350F),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Welcome Hero Banner (Styled consistently with DashboardWelcomeBanner)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                                  : [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.88)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : colorScheme.primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.black : colorScheme.primary).withValues(alpha: 0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                                    ),
                                    child: const Icon(Icons.storefront_rounded, size: 24, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          storeName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            letterSpacing: -0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            if (username.isNotEmpty) ...[
                                              Text(
                                                '@$username • ',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.white.withValues(alpha: 0.88),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                            Expanded(
                                              child: Text(
                                                'Dealer: $dealerName',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.white.withValues(alpha: 0.88),
                                                  fontWeight: FontWeight.w500,
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
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: isOrderingEnabled
                                      ? () => widget.onNavigateToTab?.call(1)
                                      : null,
                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 19),
                                  label: const Text('Start New Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: isDark ? const Color(0xFF0F172A) : colorScheme.primary,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Active Orders Summary Card
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2430) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Open Orders', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (openOrders.isNotEmpty ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8))
                                          .withValues(alpha: isDark ? 0.25 : 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: (openOrders.isNotEmpty ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8))
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Text(
                                      '${openOrders.length} In Progress',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: openOrders.isNotEmpty
                                            ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                                            : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B)),
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
                                    color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.4 : 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF10B981), size: 20),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Next Scheduled Delivery',
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              _dateFormat.format(nextDelivery),
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                                label: const Text('View All Orders', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Last Order Card with 1-Click Reorder
                        if (lastOrder != null) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E2430) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Most Recent Order', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#${lastOrder.orderNumber}',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${lastOrder.items.length} items',
                                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      _currency.format(lastOrder.approvedTotal ?? lastOrder.estimatedTotal),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
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
                                        label: const Text('Details', style: TextStyle(fontWeight: FontWeight.w600)),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: isOrderingEnabled ? () => _quickReorder(lastOrder) : null,
                                        icon: const Icon(Icons.replay_rounded, size: 16),
                                        label: const Text('Reorder', style: TextStyle(fontWeight: FontWeight.w700)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colorScheme.primary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
