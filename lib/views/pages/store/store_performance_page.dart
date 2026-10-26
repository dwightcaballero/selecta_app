import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/models/users.dart';

/// Store Performance & Analytics Dashboard (Read-Only).
/// Allows store owners to see their purchasing velocity, fill rate,
/// spending trends, and top selling products over 7, 30, and 90 days.
class StorePerformancePage extends StatefulWidget {
  const StorePerformancePage({super.key});

  @override
  State<StorePerformancePage> createState() => _StorePerformancePageState();
}

class _StorePerformancePageState extends State<StorePerformancePage> {
  int _selectedDays = 30; // 7, 30, 90
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;
        final storeName = user.storeName;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Store Analytics'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period selector segmented buttons
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 7, label: Text('7 Days')),
                          ButtonSegment(value: 30, label: Text('30 Days')),
                          ButtonSegment(value: 90, label: Text('90 Days')),
                        ],
                        selected: {_selectedDays},
                        onSelectionChanged: (val) {
                          setState(() => _selectedDays = val.first);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Deliveries & Orders Stream Aggregation
                StreamBuilder<QuerySnapshot>(
                  stream: Firebase.apps.isEmpty
                      ? const Stream<QuerySnapshot>.empty()
                      : FirebaseFirestore.instance
                          .collection('delivery')
                          .where('storeName', isEqualTo: storeName)
                          .snapshots(),
                  builder: (context, deliverySnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: Firebase.apps.isEmpty
                          ? const Stream<QuerySnapshot>.empty()
                          : FirebaseFirestore.instance
                              .collection('store_orders')
                              .where('storeId', isEqualTo: storeId)
                              .snapshots(),
                      builder: (context, orderSnapshot) {
                        final cutoff = DateTime.now().subtract(Duration(days: _selectedDays));

                        final deliveryDocs = (deliverySnapshot.data?.docs ?? []).where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final date = (data['deliveryDate'] as Timestamp?)?.toDate();
                          return date != null && date.isAfter(cutoff);
                        }).toList();

                        final orderDocs = (orderSnapshot.data?.docs ?? []).where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final date = (data['createdAt'] as Timestamp?)?.toDate();
                          return date != null && date.isAfter(cutoff);
                        }).toList();

                        double totalPurchases = 0;
                        for (final doc in deliveryDocs) {
                          final data = doc.data() as Map<String, dynamic>;
                          totalPurchases += ((data['orderAmount'] as num?)?.toDouble() ?? 0.0);
                        }

                        final int orderCount = orderDocs.isNotEmpty ? orderDocs.length : deliveryDocs.length;
                        final double aov = orderCount > 0 ? totalPurchases / orderCount : 0.0;

                        // Fill rate calculation
                        int totalOrderedUnits = 0;
                        int totalApprovedUnits = 0;
                        final Map<String, int> topProducts = {};

                        for (final doc in orderDocs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final order = StoreOrder.fromJson(data, id: doc.id);
                          for (final item in order.items) {
                            totalOrderedUnits += item.qty;
                            totalApprovedUnits += item.qtyApproved;
                            topProducts[item.productName] = (topProducts[item.productName] ?? 0) + item.qty;
                          }
                        }

                        final double fillRate = totalOrderedUnits > 0
                            ? (totalApprovedUnits / totalOrderedUnits) * 100
                            : 100.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // KPI Cards 2x2 Grid
                            Row(
                              children: [
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Total Purchases',
                                    value: _currency.format(totalPurchases),
                                    icon: Icons.payments_rounded,
                                    accentColor: Colors.green,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Orders Placed',
                                    value: '$orderCount',
                                    icon: Icons.receipt_long_rounded,
                                    accentColor: Colors.blue,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Avg Order Value',
                                    value: _currency.format(aov),
                                    icon: Icons.analytics_outlined,
                                    accentColor: Colors.purple,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Fill Rate %',
                                    value: '${fillRate.toStringAsFixed(1)}%',
                                    icon: Icons.check_circle_outline_rounded,
                                    accentColor: fillRate >= 90 ? Colors.teal : Colors.orange,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Spend Trend Chart
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Purchasing Trend',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Order spend over the last $_selectedDays days',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      height: 180,
                                      child: _buildTrendChart(deliveryDocs, isDark, colorScheme),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Top Purchased SKUs
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Top Ordered Products',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Most frequently ordered SKUs by units',
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 16),
                                    if (topProducts.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 24),
                                        child: Center(
                                          child: Text('No order items in this period.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                        ),
                                      )
                                    else
                                      ..._buildTopProductsList(topProducts, colorScheme),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart(List<QueryDocumentSnapshot> docs, bool isDark, ColorScheme colorScheme) {
    if (docs.isEmpty) {
      return Center(
        child: Text('No orders recorded in this period.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
      );
    }

    // Sort deliveries by date
    final sorted = docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      final date = (data['deliveryDate'] as Timestamp?)?.toDate() ?? DateTime.now();
      final amt = (data['orderAmount'] as num?)?.toDouble() ?? 0.0;
      return MapEntry(date, amt);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = <FlSpot>[];
    for (int i = 0; i < sorted.length; i++) {
      spots.add(FlSpot(i.toDouble(), sorted[i].value));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (val) => FlLine(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            strokeWidth: 1,
          ),
        ),
        titlesData: const FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: colorScheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTopProductsList(Map<String, int> topProducts, ColorScheme colorScheme) {
    final sorted = topProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();
    final maxQty = top5.isNotEmpty ? top5.first.value : 1;

    return top5.map((entry) {
      final ratio = entry.value / maxQty;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${entry.value} units',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: colorScheme.primary,
            ),
          ],
        ),
      );
    }).toList();
  }
}
