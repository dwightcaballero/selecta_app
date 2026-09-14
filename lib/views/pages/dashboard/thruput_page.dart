import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class ThruputPage extends StatelessWidget {
  const ThruputPage({super.key, required this.dashboardDTO});

  final DashboardDTO dashboardDTO;

  static const double _targetThruput = 8000;

  Widget _buildThruputSummary(BuildContext context, {required double progress, required double remainingThruput}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOnTarget = remainingThruput == 0;
    final statusColor = isOnTarget ? colorScheme.primary : colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text('Thruput Progress', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: colorScheme.primary,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryValue(context, label: 'Actual', value: Helperfunctions.formatDoubleAmountForDisplay(dashboardDTO.buyingThruput)),
              const SizedBox(width: 24),
              _buildSummaryValue(
                context,
                label: isOnTarget ? 'Target reached' : 'Remaining',
                value: Helperfunctions.formatDoubleAmountForDisplay(remainingThruput),
                valueColor: statusColor,
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

  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, {required String label, required String value, required IconData icon, Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalStores = dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount;
    final averageSale = dashboardDTO.totaltransactionCount == 0 ? 0.0 : dashboardDTO.totalBuyingSales / dashboardDTO.totaltransactionCount;
    final averageTransactions = dashboardDTO.buyingCount == 0 ? 0.0 : dashboardDTO.totaltransactionCount / dashboardDTO.buyingCount;
    final remainingThruput = (_targetThruput - dashboardDTO.buyingThruput).clamp(0, _targetThruput).toDouble();
    final progress = (dashboardDTO.buyingThruput / _targetThruput).clamp(0.0, 1.0);

    return Scaffold(
      appBar: const CustomAppbar(title: 'KPI - Thruput', subtitle: 'Performance overview'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildThruputSummary(context, progress: progress, remainingThruput: remainingThruput),
          const SizedBox(height: 20),
          _buildSection(
            context,
            title: 'Store Coverage',
            icon: Icons.storefront_outlined,
            children: [
              _buildMetricRow(context, label: 'Total stores', value: '$totalStores', icon: Icons.business_outlined),
              _buildMetricRow(
                context,
                label: 'Buying stores',
                value: '${dashboardDTO.buyingCount}',
                icon: Icons.check_circle_outline,
                valueColor: Theme.of(context).colorScheme.primary,
              ),
              _buildMetricRow(
                context,
                label: 'Non-buying stores',
                value: '${dashboardDTO.nonBuyingCount}',
                icon: Icons.remove_shopping_cart_outlined,
                valueColor: Theme.of(context).colorScheme.error,
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
              ),
              _buildMetricRow(context, label: 'Transactions', value: '${dashboardDTO.totaltransactionCount}', icon: Icons.receipt_outlined),
              _buildMetricRow(
                context,
                label: 'Average sale per transaction',
                value: Helperfunctions.formatDoubleAmountForDisplay(averageSale),
                icon: Icons.trending_up_outlined,
              ),
              _buildMetricRow(
                context,
                label: 'Average transactions per store',
                value: averageTransactions.toStringAsFixed(2),
                icon: Icons.analytics_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
