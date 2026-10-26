import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBorder = isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E2430) : Colors.white;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;
        final storeName = user.storeName;

        return Scaffold(
          appBar: const CustomAppbar(
            title: 'Store Analytics',
            subtitle: 'Spending & purchasing performance',
            showBackButton: false,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period selector segmented pills
                Row(
                  children: [7, 30, 90].map((days) {
                    final isSelected = _selectedDays == days;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _selectedDays = days),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary
                                  : (isDark ? const Color(0xFF1E2430) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : cardBorder,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$days Days',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
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
                                    accentColor: const Color(0xFF10B981),
                                    isDark: isDark,
                                    cardBg: cardBg,
                                    cardBorder: cardBorder,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Orders Placed',
                                    value: '$orderCount',
                                    icon: Icons.receipt_long_rounded,
                                    accentColor: const Color(0xFF3B82F6),
                                    isDark: isDark,
                                    cardBg: cardBg,
                                    cardBorder: cardBorder,
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
                                    accentColor: const Color(0xFF8B5CF6),
                                    isDark: isDark,
                                    cardBg: cardBg,
                                    cardBorder: cardBorder,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildKpiTile(
                                    label: 'Fill Rate %',
                                    value: '${fillRate.toStringAsFixed(1)}%',
                                    icon: Icons.check_circle_outline_rounded,
                                    accentColor: fillRate >= 90 ? const Color(0xFF0D9488) : const Color(0xFFF59E0B),
                                    isDark: isDark,
                                    cardBg: cardBg,
                                    cardBorder: cardBorder,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Spend Trend Chart
                            Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cardBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
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
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Purchasing Trend',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Spend over the last $_selectedDays days',
                                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.show_chart_rounded, size: 18, color: colorScheme.primary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    height: 180,
                                    child: _buildTrendChart(deliveryDocs, isDark, colorScheme),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Top Purchased SKUs
                            Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cardBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
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
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Top Ordered Products',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Most ordered SKUs by units',
                                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (topProducts.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text(
                                          'No order items in this period.',
                                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                                        ),
                                      ),
                                    )
                                  else
                                    ..._buildTopProductsList(topProducts, colorScheme, cardBorder),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
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
    required Color cardBg,
    required Color cardBorder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(List<QueryDocumentSnapshot> docs, bool isDark, ColorScheme colorScheme) {
    if (docs.isEmpty) {
      return Center(
        child: Text('No orders recorded in this period.', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
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

  List<Widget> _buildTopProductsList(Map<String, int> topProducts, ColorScheme colorScheme, Color cardBorder) {
    final sorted = topProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();
    final maxQty = top5.isNotEmpty ? top5.first.value : 1;

    return top5.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final ratio = item.value / maxQty;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? const Color(0xFFF59E0B)
                        : (index == 1
                            ? const Color(0xFF94A3B8)
                            : (index == 2 ? const Color(0xFFB45309) : colorScheme.surfaceContainerHighest)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: index < 3 ? Colors.white : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.key,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${item.value} units',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
