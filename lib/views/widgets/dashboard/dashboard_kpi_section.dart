import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/views/pages/dashboard/buyinglist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/expansion_page.dart';
import 'package:selecta_ops/views/pages/dashboard/placementlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/sales_page.dart';
import 'package:selecta_ops/views/pages/dashboard/scanninglist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/thruput_page.dart';

/// KPI Section displaying 6 progress donut charts and metrics:
/// Sales, Buying Stores, Throughput, Placement, Scanning, and Expansion.
class DashboardKpiSection extends StatelessWidget {
  final DashboardDTO dashboardDTO;
  final Configuration? configuration;
  final bool isSyncing;
  final Future<void> Function(Widget page) onNavigate;

  const DashboardKpiSection({
    super.key,
    required this.dashboardDTO,
    required this.configuration,
    required this.isSyncing,
    required this.onNavigate,
  });

  Color _mutedChartColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF2E3644) : const Color(0xFFE2E8F0);
  }

  Color _metricColor(BuildContext context, String metric) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    if (isDark) {
      return switch (metric) {
        'sales' => const Color(0xFF22C55E), // Vibrant Green 500
        'buying' => const Color(0xFF60A5FA), // Crisp Blue 400
        'throughput' => const Color(0xFFA855F7), // Purple 500
        'placement' => const Color(0xFF22D3EE), // Cyan 400
        'scanning' => const Color(0xFFFBBF24), // Warm Amber 400
        'expansion' => const Color(0xFF2DD4BF), // Teal 400
        _ => colorScheme.primary,
      };
    }

    return switch (metric) {
      'sales' => const Color(0xFF15803D),
      'buying' => const Color(0xFF2563EB),
      'throughput' => const Color(0xFF7C3AED),
      'placement' => const Color(0xFF0891B2),
      'scanning' => const Color(0xFFD97706),
      'expansion' => const Color(0xFF0F766E),
      _ => colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSalesCard(context)),
            const SizedBox(width: 10),
            Expanded(child: _buildBuyingCard(context)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildThruputCard(context)),
            const SizedBox(width: 10),
            Expanded(child: _buildPlacementCard(context)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildScanningCard(context)),
            const SizedBox(width: 10),
            Expanded(child: _buildExpansionCard(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildSalesCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'sales');
    final double target = configuration?.salesTarget ?? 1000000;
    final double sales = dashboardDTO.totalInvoiceAmount;
    final double missing = (target - sales) < 0 ? 0 : (target - sales);
    final double percentage = target <= 0 ? 0 : (sales / target);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return _buildCardWrapper(
      context,
      title: 'Sales',
      icon: Icons.attach_money_rounded,
      accent: accent,
      nextPage: SalesPage(monthlyTarget: target),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: sales <= 0 ? 0.01 : sales,
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missing <= 0 ? 0.01 : missing,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Invoiced', currencyFormat.format(sales), accent),
          _buildLegendRow(context, 'Missing', currencyFormat.format(missing), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target', currencyFormat.format(target), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildBuyingCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'buying');
    final int allStores = dashboardDTO.totalHapiStores > 0
        ? dashboardDTO.totalHapiStores
        : (dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount);
    final double buyingTargetPct = (configuration?.buyingTargetPercentage ?? 80.0) / 100.0;
    double target = isSyncing ? 1 : (allStores * buyingTargetPct).roundToDouble();
    if (target == 0 && allStores > 0) target = 1;
    double buyingCount = isSyncing ? 0 : dashboardDTO.buyingCount.toDouble();
    double missing = (target - buyingCount).clamp(0.0, double.infinity);
    final percentage = target == 0 ? 0.0 : (buyingCount / target);

    return _buildCardWrapper(
      context,
      title: 'Buying Stores',
      icon: Icons.shopping_cart_outlined,
      accent: accent,
      nextPage: const BuyinglistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: buyingCount <= 0 ? 0.01 : buyingCount,
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missing <= 0 ? 0.01 : missing,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Buying', buyingCount.toStringAsFixed(0), accent),
          _buildLegendRow(context, 'Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target (80%)', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildThruputCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'throughput');
    double buyingThruput = isSyncing ? 0 : dashboardDTO.buyingThruput;
    double thruputTarget = configuration?.throughputTarget ?? 8000;
    final missingThruput = (thruputTarget - buyingThruput).clamp(0.0, double.infinity);
    final percentage = thruputTarget == 0 ? 0.0 : (buyingThruput / thruputTarget);

    return _buildCardWrapper(
      context,
      title: 'Throughput',
      icon: Icons.speed_outlined,
      accent: accent,
      nextPage: ThruputPage(dashboardDTO: dashboardDTO, throughputTarget: thruputTarget),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: buyingThruput <= 0 ? 0.01 : buyingThruput,
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missingThruput <= 0 ? 0.01 : missingThruput,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Actual', Helperfunctions.formatDoubleAmountForDisplay(buyingThruput), accent),
          _buildLegendRow(context, 'Missing', Helperfunctions.formatDoubleAmountForDisplay(missingThruput), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target', Helperfunctions.formatDoubleAmountForDisplay(thruputTarget), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildPlacementCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'placement');
    final int allStores = dashboardDTO.totalHapiStores > 0
        ? dashboardDTO.totalHapiStores
        : (dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount);
    final double placementTargetPct = (configuration?.placementTargetPercentage ?? 80.0) / 100.0;
    double actual = isSyncing ? 0 : dashboardDTO.totalPlacementCount.toDouble();
    double target = isSyncing ? 1 : (allStores * placementTargetPct).roundToDouble();
    if (target == 0 && allStores > 0) target = 1;
    double missing = (target - actual).clamp(0.0, double.infinity);
    final percentage = target == 0 ? 0.0 : (actual / target);

    return _buildCardWrapper(
      context,
      title: 'Placement',
      icon: Icons.grid_view_outlined,
      accent: accent,
      nextPage: const PlacementlistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: actual <= 0 ? 0.01 : actual,
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missing <= 0 ? 0.01 : missing,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Actual', actual.toStringAsFixed(0), accent),
          _buildLegendRow(context, 'Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target (80%)', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildScanningCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'scanning');
    final scanned = isSyncing ? 0 : dashboardDTO.totalScanCount;
    final notScanned = isSyncing ? 0 : dashboardDTO.totalNotScannedCount;
    final total = scanned + notScanned;
    final double scanningTargetPct = (configuration?.scanningTargetPercentage ?? 100.0) / 100.0;
    final double target = (total * scanningTargetPct).roundToDouble();
    final double missing = (target - scanned).clamp(0.0, double.infinity);
    final percentage = target == 0 ? 0.0 : (scanned / target);

    return _buildCardWrapper(
      context,
      title: 'Scanning',
      icon: Icons.qr_code_scanner_outlined,
      accent: accent,
      nextPage: const ScanninglistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: scanned <= 0 ? 0.01 : scanned.toDouble(),
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missing <= 0 ? 0.01 : missing,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Scanned', scanned.toString(), accent),
          _buildLegendRow(context, 'Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target (100%)', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildExpansionCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'expansion');
    final double target = (configuration?.expansionTarget ?? 10).toDouble();
    double opened = isSyncing ? 0 : dashboardDTO.totalExpansionCount.toDouble();
    double missing = (target - opened).clamp(0.0, double.infinity);
    final percentage = target == 0 ? 0.0 : (opened / target);

    return _buildCardWrapper(
      context,
      title: 'Expansion',
      icon: Icons.trending_up_outlined,
      accent: accent,
      nextPage: ExpansionPage(monthlyTarget: target.toInt()),
      child: Column(
        children: [
          SizedBox(
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: opened <= 0 ? 0.01 : opened,
                        color: accent,
                        showTitle: false,
                        radius: 18,
                      ),
                      PieChartSectionData(
                        value: missing <= 0 ? 0.01 : missing,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 16,
                      ),
                    ],
                  ),
                ),
                Text(
                  NumberFormat('0%').format(percentage),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow(context, 'Opened', opened.toStringAsFixed(0), accent),
          _buildLegendRow(context, 'Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow(context, 'Target', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildCardWrapper(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
    required Widget nextPage,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final cardAccent = accent ?? colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      elevation: isDark ? 2 : 1.5,
      shadowColor: Colors.black.withAlpha(isDark ? 50 : 20),
      color: theme.cardTheme.color ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? cardAccent.withAlpha(75) : cardAccent.withAlpha(50),
          width: isDark ? 1.2 : 1.1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onNavigate(nextPage),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4.5),
                    decoration: BoxDecoration(
                      color: cardAccent.withAlpha(isDark ? 42 : 22),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon, size: 15, color: cardAccent),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 10, color: colorScheme.onSurfaceVariant.withAlpha(150)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(
                  height: 1,
                  thickness: 0.8,
                  color: colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendRow(BuildContext context, String label, String value, Color dotColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
