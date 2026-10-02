import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

enum AnalyticsTimeframe {
  past7Days('7 Days', 7),
  past30Days('30 Days', 30),
  past90Days('90 Days', 90);

  final String label;
  final int days;
  const AnalyticsTimeframe(this.label, this.days);
}

class DailyDataPoint {
  final DateTime date;
  final double sales;
  final int deliveries;

  DailyDataPoint({required this.date, required this.sales, required this.deliveries});
}

/// Historical Performance & Analytics Page displaying multi-day trends for Sales,
/// Deliveries, and Store Visits using fl_chart charts.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  AnalyticsTimeframe _selectedTimeframe = AnalyticsTimeframe.past7Days;
  bool _isLoading = true;

  Configuration? _configuration;
  List<DailyDataPoint> _dataPoints = [];
  double _totalSales = 0.0;
  int _totalDeliveries = 0;
  int _totalVisits = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedTimeframe.days - 1));

      // 1. Load config
      _configuration = await ConfigurationService().getConfiguration();

      // 2. Fetch purchase orders / invoiced sales
      final poSnapshot = await FirebaseFirestore.instance
          .collection(PURCHASEORDER_COLLECTION_REF)
          .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      // 3. Fetch completed deliveries
      final deliverySnapshot = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where('createdDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      // 4. Fetch store visits
      final visitSnapshot = await FirebaseFirestore.instance
          .collection(PROOF_OF_VISIT_COLLECTION)
          .where('visitDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .get();

      final Map<String, double> salesMap = {};
      final Map<String, int> deliveryMap = {};

      for (int i = 0; i < _selectedTimeframe.days; i++) {
        final d = startDate.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        salesMap[key] = 0.0;
        deliveryMap[key] = 0;
      }

      double totalSalesAcc = 0;
      for (final doc in poSnapshot.docs) {
        final po = Purchaseorder.fromJson(doc.data());
        final key = DateFormat('yyyy-MM-dd').format(po.orderDate.toDate());
        final amount = po.invoiceAmount > 0 ? po.invoiceAmount : po.orderAmount;
        if (salesMap.containsKey(key)) {
          salesMap[key] = (salesMap[key] ?? 0) + amount;
        }
        totalSalesAcc += amount;
      }

      int totalDelAcc = 0;
      for (final doc in deliverySnapshot.docs) {
        final del = Delivery.fromJson(doc.data());
        final key = DateFormat('yyyy-MM-dd').format(del.createdDate.toDate());
        if (deliveryMap.containsKey(key)) {
          deliveryMap[key] = (deliveryMap[key] ?? 0) + 1;
        }
        totalDelAcc++;
      }

      final List<DailyDataPoint> points = [];
      for (int i = 0; i < _selectedTimeframe.days; i++) {
        final d = startDate.add(Duration(days: i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        points.add(
          DailyDataPoint(
            date: d,
            sales: salesMap[key] ?? 0.0,
            deliveries: deliveryMap[key] ?? 0,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _dataPoints = points;
          _totalSales = totalSalesAcc;
          _totalDeliveries = totalDelAcc;
          _totalVisits = visitSnapshot.docs.length;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'AnalyticsPage',
        action: 'Load Historical Analytics',
        error: e,
        stackTrace: s,
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Historical Analytics',
        subtitle: 'Sales, delivery trends & operational performance',
      ),
      body: RefreshIndicator(
        onRefresh: _loadAnalytics,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Timeframe Selector ───────────────────────────────────────
              _buildTimeframeSelector(colorScheme),

              const SizedBox(height: 16),

              if (_isLoading) ...[
                const ShimmerBox(height: 90, borderRadius: 14),
                const SizedBox(height: 14),
                const ShimmerBox(height: 260, borderRadius: 14),
                const SizedBox(height: 14),
                const ShimmerBox(height: 220, borderRadius: 14),
              ] else ...[
                // ── KPI Summary Cards ──────────────────────────────────────
                _buildSummaryGrid(colorScheme),

                const SizedBox(height: 20),

                // ── Sales Trend Line Chart ─────────────────────────────────
                _buildSalesTrendCard(colorScheme),

                const SizedBox(height: 16),

                // ── Delivery Volume Bar Chart ──────────────────────────────
                _buildDeliveryVolumeCard(colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeframeSelector(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: AnalyticsTimeframe.values.map((tf) {
          final isSelected = _selectedTimeframe == tf;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                if (_selectedTimeframe != tf) {
                  setState(() => _selectedTimeframe = tf);
                  _loadAnalytics();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  tf.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryGrid(ColorScheme colorScheme) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
    final target = _configuration?.salesTarget ?? 1000000.0;
    final targetPct = target > 0 ? (_totalSales / target * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Total Sales',
            value: currency.format(_totalSales),
            subtitle: '$targetPct% of target',
            icon: Icons.payments_outlined,
            color: const Color(0xFF15803D),
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'Deliveries',
            value: '$_totalDeliveries',
            subtitle: 'Completed',
            icon: Icons.local_shipping_outlined,
            color: colorScheme.primary,
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            title: 'Store Visits',
            value: '$_totalVisits',
            subtitle: 'Verified PJP',
            icon: Icons.storefront_outlined,
            color: const Color(0xFF7C3AED),
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTrendCard(ColorScheme colorScheme) {
    if (_dataPoints.isEmpty) return const SizedBox.shrink();

    final maxSales = _dataPoints.map((p) => p.sales).fold(0.0, math.max);
    final maxY = maxSales <= 0 ? 1000.0 : (maxSales * 1.25);

    final spots = <FlSpot>[];
    for (int i = 0; i < _dataPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dataPoints[i].sales));
    }

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF15803D), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Sales Revenue Trend',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Daily invoiced sales over the selected period',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < _dataPoints.length) {
                            if (_dataPoints.length > 10 && idx % (_dataPoints.length ~/ 5) != 0) {
                              return const SizedBox.shrink();
                            }
                            final date = _dataPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                DateFormat('M/d').format(date),
                                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (val, meta) {
                          if (val == 0) return const SizedBox.shrink();
                          return Text(
                            Helperfunctions.formatDoubleAmountForDisplay(val),
                            style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (_dataPoints.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: const Color(0xFF15803D),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: _dataPoints.length <= 14,
                        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                          radius: 3.5,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: const Color(0xFF15803D),
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF15803D).withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryVolumeCard(ColorScheme colorScheme) {
    if (_dataPoints.isEmpty) return const SizedBox.shrink();

    final maxDel = _dataPoints.map((p) => p.deliveries).fold(0, math.max);
    final maxY = maxDel <= 0 ? 5.0 : (maxDel * 1.3);

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < _dataPoints.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _dataPoints[i].deliveries.toDouble(),
              color: colorScheme.primary,
              width: _dataPoints.length <= 7 ? 16 : 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Daily Delivery Volume',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Completed dealer order fulfillment counts',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < _dataPoints.length) {
                            if (_dataPoints.length > 10 && idx % (_dataPoints.length ~/ 5) != 0) {
                              return const SizedBox.shrink();
                            }
                            final date = _dataPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                DateFormat('M/d').format(date),
                                style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (val, meta) {
                          if (val == 0) return const SizedBox.shrink();
                          return Text(
                            '${val.toInt()}',
                            style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: barGroups,
                  maxY: maxY,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
