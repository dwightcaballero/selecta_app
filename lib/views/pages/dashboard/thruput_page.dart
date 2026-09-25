import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/views/pages/dashboard/buyinglist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class ThruputPage extends StatelessWidget {
  const ThruputPage({super.key, required this.dashboardDTO});

  final DashboardDTO dashboardDTO;

  static const double _targetThruput = 8000;

  Widget _buildThruputSummary(
    BuildContext context, {
    required double safeThruput,
    required double progress,
    required double remainingThruput,
    required bool isOnTarget,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    final surplus = (safeThruput - _targetThruput).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.speed_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Throughput Progress',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$currentMonth • Target: ${Helperfunctions.formatDoubleAmountForDisplay(_targetThruput)} / store',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnTarget ? Colors.green.withValues(alpha: 0.12) : colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isOnTarget ? Colors.green : colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: isOnTarget ? Colors.green : colorScheme.primary,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildSummaryValue(
                context,
                label: 'Actual Throughput',
                value: Helperfunctions.formatDoubleAmountForDisplay(safeThruput),
                valueColor: isOnTarget ? Colors.green : null,
              ),
              const SizedBox(width: 20),
              _buildSummaryValue(
                context,
                label: isOnTarget ? 'Status' : 'Remaining to Target',
                value: isOnTarget
                    ? (surplus > 0 ? '+${Helperfunctions.formatDoubleAmountForDisplay(surplus)} over' : 'Target reached! 🎉')
                    : Helperfunctions.formatDoubleAmountForDisplay(remainingThruput),
                valueColor: isOnTarget ? Colors.green : colorScheme.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryValue(BuildContext context, {required String label, required String value, Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor ?? colorScheme.onSurface),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Safe calculation preventing NaN crash if buyingCount is 0
    final safeThruput = dashboardDTO.buyingThruput.isNaN ? 0.0 : dashboardDTO.buyingThruput;
    final totalStores = dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount;
    final conversionRate = totalStores == 0 ? 0.0 : (dashboardDTO.buyingCount / totalStores * 100);

    final averageSale = dashboardDTO.totaltransactionCount == 0
        ? 0.0
        : dashboardDTO.totalBuyingSales / dashboardDTO.totaltransactionCount;
    final averageTransactions = dashboardDTO.buyingCount == 0
        ? 0.0
        : dashboardDTO.totaltransactionCount / dashboardDTO.buyingCount;

    final remainingThruput = (_targetThruput - safeThruput).clamp(0.0, _targetThruput);
    final progress = (_targetThruput == 0 ? 0.0 : (safeThruput / _targetThruput)).clamp(0.0, 1.0);
    final isOnTarget = safeThruput >= _targetThruput;

    return Scaffold(
      appBar: const CustomAppbar(title: 'KPI - Throughput', subtitle: 'Store throughput and activity'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildThruputSummary(
            context,
            safeThruput: safeThruput,
            progress: progress,
            remainingThruput: remainingThruput,
            isOnTarget: isOnTarget,
          ),
          const SizedBox(height: 18),
          _buildSection(
            context,
            title: 'Store Coverage',
            icon: Icons.storefront_outlined,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${conversionRate.toStringAsFixed(1)}% Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            children: [
              _buildMetricRow(
                context,
                label: 'Total accounts',
                value: '$totalStores stores',
                icon: Icons.business_outlined,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildMetricRow(
                context,
                label: 'Buying stores',
                value: '${dashboardDTO.buyingCount}',
                icon: Icons.check_circle_outline,
                valueColor: Theme.of(context).colorScheme.primary,
                onTap: () => Helperfunctions.navigateTo(context, const BuyinglistPage()),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildMetricRow(
                context,
                label: 'Non-buying stores',
                value: '${dashboardDTO.nonBuyingCount}',
                icon: Icons.remove_shopping_cart_outlined,
                valueColor: Theme.of(context).colorScheme.error,
                onTap: () => Helperfunctions.navigateTo(context, const BuyinglistPage()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSection(
            context,
            title: 'Sales Activity',
            icon: Icons.receipt_long_outlined,
            children: [
              _buildMetricRow(
                context,
                label: 'Buying store sales',
                value: Helperfunctions.formatDoubleAmountForDisplay(dashboardDTO.totalBuyingSales),
                icon: Icons.payments_outlined,
                valueColor: Theme.of(context).colorScheme.primary,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildMetricRow(
                context,
                label: 'Total transactions',
                value: '${dashboardDTO.totaltransactionCount}',
                icon: Icons.receipt_outlined,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildMetricRow(
                context,
                label: 'Average sale per transaction',
                value: Helperfunctions.formatDoubleAmountForDisplay(averageSale),
                icon: Icons.trending_up_outlined,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildMetricRow(
                context,
                label: 'Average transactions per store',
                value: averageTransactions.toStringAsFixed(1),
                icon: Icons.analytics_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
