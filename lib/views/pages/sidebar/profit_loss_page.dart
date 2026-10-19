import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/profit_loss_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/dto/profit_loss_dto.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

class ProfitLossPage extends StatefulWidget {
  const ProfitLossPage({super.key});

  @override
  State<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends State<ProfitLossPage> {
  final ProfitLossController _controller = ProfitLossController();

  ProfitLossPeriod _selectedPeriod = ProfitLossPeriod.thisMonth;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  bool _isLoading = true;
  String? _errorMessage;
  ProfitLossDTO _data = ProfitLossDTO.empty();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final range = ProfitLossDateRange.forPeriod(_selectedPeriod, customStart: _customStartDate, customEnd: _customEndDate);

      final result = await _controller.computeProfitLoss(range);
      if (mounted) {
        setState(() {
          _data = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load analytics: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final initialStart = _customStartDate ?? DateTime(now.year, now.month, 1);
    final initialEnd = _customEndDate ?? now;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(
        start: initialStart.isBefore(DateTime(2020)) ? DateTime(2020) : initialStart,
        end: initialEnd.isAfter(DateTime(now.year + 2)) ? now : initialEnd,
      ),
      helpText: 'Select Date Range for Business Analytics',
      saveText: 'Apply',
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = ProfitLossPeriod.custom;
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Business Analytics',
          subtitle: 'Profit & Loss, Cost of Goods, etc.',
          actions: [
            IconButton(
              icon: const Icon(Icons.date_range_outlined, color: Colors.white),
              tooltip: 'Custom Date Range',
              onPressed: _selectCustomDateRange,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              spacing: 20,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period Filter Chips
                _buildPeriodChips(colorScheme, isDark),

                // Active Date Range Label & Health Badge
                _buildDateRangeHeader(colorScheme, isDark),

                if (_isLoading)
                  _buildLoadingState(colorScheme)
                else if (_errorMessage != null)
                  _buildErrorState(colorScheme)
                else ...[
                  // KPI Summary Cards Row
                  _buildSummaryCards(colorScheme, isDark),

                  if (ScreenSize.isTabletLandscape(context))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Trend & Operations Volume
                        Expanded(
                          flex: 5,
                          child: Column(
                            spacing: 20,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTrendChart(colorScheme, isDark),
                              _buildVolumeStatsCard(colorScheme, isDark),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // Right Column: Detailed P&L Income Statement Breakdown
                        Expanded(
                          flex: 5,
                          child: _buildBreakdownCard(colorScheme, isDark),
                        ),
                      ],
                    )
                  else ...[
                    // Trend Chart
                    _buildTrendChart(colorScheme, isDark),

                    // Detailed P&L Income Statement Card
                    _buildBreakdownCard(colorScheme, isDark),

                    // Operations & Volume Stats Card
                    _buildVolumeStatsCard(colorScheme, isDark),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodChips(ColorScheme colorScheme, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in ProfitLossPeriod.values) ...[
            ChoiceChip(
              label: Text(
                period == ProfitLossPeriod.custom && _selectedPeriod == ProfitLossPeriod.custom && _customStartDate != null
                    ? 'Custom (${DateFormat('M/d').format(_customStartDate!)} - ${DateFormat('M/d').format(_customEndDate ?? _customStartDate!)})'
                    : period.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: _selectedPeriod == period ? FontWeight.bold : FontWeight.normal,
                  color: _selectedPeriod == period ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                ),
              ),
              selected: _selectedPeriod == period,
              selectedColor: colorScheme.primary,
              backgroundColor: isDark ? const Color(0xFF1E2430) : Colors.grey.shade100,
              side: BorderSide(color: _selectedPeriod == period ? colorScheme.primary : (isDark ? const Color(0xFF2E3644) : Colors.grey.shade300)),
              onSelected: (selected) {
                if (selected) {
                  if (period == ProfitLossPeriod.custom) {
                    _selectCustomDateRange();
                  } else {
                    setState(() => _selectedPeriod = period);
                    _loadData();
                  }
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDateRangeHeader(ColorScheme colorScheme, bool isDark) {
    final startFormatted = DateFormat('MMM d, yyyy').format(_data.periodStart);
    final endFormatted = DateFormat('MMM d, yyyy').format(_data.periodEnd);
    final dateRangeText =
        _data.periodStart.year == _data.periodEnd.year &&
            _data.periodStart.month == _data.periodEnd.month &&
            _data.periodStart.day == _data.periodEnd.day
        ? startFormatted
        : '$startFormatted  –  $endFormatted';

    final margin = _data.netMarginPercent;

    Color badgeBg;
    Color badgeTextColor;
    String badgeText;
    IconData badgeIcon;

    if (margin >= 15.0) {
      badgeBg = const Color(0xFF10B981).withValues(alpha: 0.15);
      badgeTextColor = const Color(0xFF059669);
      badgeText = 'Healthy (${margin.toStringAsFixed(1)}%)';
      badgeIcon = Icons.trending_up_rounded;
    } else if (margin > 0.0) {
      badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      badgeTextColor = const Color(0xFFD97706);
      badgeText = 'Moderate (${margin.toStringAsFixed(1)}%)';
      badgeIcon = Icons.remove_rounded;
    } else {
      badgeBg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      badgeTextColor = const Color(0xFFDC2626);
      badgeText = 'Loss (${margin.toStringAsFixed(1)}%)';
      badgeIcon = Icons.trending_down_rounded;
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              dateRangeText,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        if (!_isLoading && _errorMessage == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 14, color: badgeTextColor),
                const SizedBox(width: 4),
                Text(
                  badgeText,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeTextColor),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Container(
      height: 300,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: 16),
          Text('Analyzing sales, costs, and expenses...', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 40),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'An error occurred',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: const Text('Try Again')),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ColorScheme colorScheme, bool isDark) {
    final isGrossProfitPositive = _data.grossProfit >= 0;
    final isNetProfitPositive = _data.netProfit >= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;

        final cards = [
          _buildMetricCard(
            title: 'Net Revenue',
            amount: _data.netRevenue,
            subtitle: 'Gross: ${Helperfunctions.formatDoubleAmountForDisplay(_data.grossRevenue)}',
            icon: Icons.payments_rounded,
            iconColor: const Color(0xFF0284C7),
            cardBg: isDark ? const Color(0xFF162534) : const Color(0xFFF0F9FF),
            borderColor: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFBAE6FD),
            colorScheme: colorScheme,
            isDark: isDark,
          ),
          _buildMetricCard(
            title: 'Cost of Goods',
            amount: _data.netCOGS,
            subtitle: 'Inventory acquisition cost',
            icon: Icons.inventory_2_rounded,
            iconColor: const Color(0xFFD97706),
            cardBg: isDark ? const Color(0xFF2C2214) : const Color(0xFFFFFBEB),
            borderColor: isDark ? const Color(0xFF593F16) : const Color(0xFFFDE68A),
            colorScheme: colorScheme,
            isDark: isDark,
          ),
          _buildMetricCard(
            title: 'Gross Profit',
            amount: _data.grossProfit,
            subtitle: 'Margin: ${_data.grossMarginPercent.toStringAsFixed(1)}%',
            icon: Icons.account_balance_wallet_rounded,
            iconColor: isGrossProfitPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            cardBg: isGrossProfitPositive
                ? (isDark ? const Color(0xFF142921) : const Color(0xFFECFDF5))
                : (isDark ? const Color(0xFF2D1616) : const Color(0xFFFEF2F2)),
            borderColor: isGrossProfitPositive
                ? (isDark ? const Color(0xFF1B4D3E) : const Color(0xFFA7F3D0))
                : (isDark ? const Color(0xFF5A1D1D) : const Color(0xFFFECACA)),
            colorScheme: colorScheme,
            isDark: isDark,
          ),
          _buildMetricCard(
            title: 'Net Profit (Earnings)',
            amount: _data.netProfit,
            subtitle: 'Net Margin: ${_data.netMarginPercent.toStringAsFixed(1)}%',
            icon: Icons.savings_rounded,
            iconColor: isNetProfitPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
            cardBg: isNetProfitPositive
                ? (isDark ? const Color(0xFF0F2E22) : const Color(0xFFE6F4EA))
                : (isDark ? const Color(0xFF331414) : const Color(0xFFFCE8E6)),
            borderColor: isNetProfitPositive
                ? (isDark ? const Color(0xFF105C3F) : const Color(0xFF86EFAC))
                : (isDark ? const Color(0xFF701A1A) : const Color(0xFFFCA5A5)),
            colorScheme: colorScheme,
            isDark: isDark,
          ),
        ];

        if (isNarrow) {
          return GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            children: cards,
          );
        } else {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cards
                  .map(
                    (card) => Expanded(
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: card),
                    ),
                  )
                  .toList(),
            ),
          );
        }
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required double amount,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardBg,
    required Color borderColor,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Helperfunctions.formatDoubleAmountForDisplay(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: amount < 0 ? const Color(0xFFEF4444) : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(ColorScheme colorScheme, bool isDark) {
    final points = _data.trendPoints;
    final hasData = points.isNotEmpty && points.any((p) => p.revenue > 0 || p.cost > 0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF2E3644) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revenue vs. Cost Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                'Comparing Net Sales against Total Costs (COGS + Expenses + Bad Orders)',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Legend
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildLegendItem(const Color(0xFF10B981), 'Net Revenue'),
              _buildLegendItem(const Color(0xFFEF4444), 'Total Costs'),
              _buildLegendItem(const Color(0xFF6366F1), 'Net Profit Gap'),
            ],
          ),
          const SizedBox(height: 22),

          if (!hasData)
            Container(
              height: 220,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.query_stats_outlined, size: 44, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text('No transaction or cost records found for this period', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            SizedBox(height: 240, child: _buildLineChartWidget(points, colorScheme, isDark)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLineChartWidget(List<ProfitLossTrendPoint> points, ColorScheme colorScheme, bool isDark) {
    final revenueSpots = <FlSpot>[];
    final costSpots = <FlSpot>[];

    double maxVal = 0.0;
    for (int i = 0; i < points.length; i++) {
      final rev = points[i].revenue;
      final cost = points[i].cost;
      revenueSpots.add(FlSpot(i.toDouble(), rev));
      costSpots.add(FlSpot(i.toDouble(), cost));

      maxVal = math.max(maxVal, math.max(rev, cost));
    }

    final maxY = maxVal <= 0 ? 1000.0 : maxVal * 1.25;
    final maxX = (points.length - 1).toDouble().clamp(1.0, double.infinity);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (val) => FlLine(color: isDark ? const Color(0xFF2E3644) : Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < points.length) {
                  // If too many points, skip some labels to avoid clutter
                  if (points.length > 12 && idx % (points.length ~/ 6) != 0 && idx != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[idx].label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
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
              reservedSize: 48,
              getTitlesWidget: (val, meta) {
                if (val == 0) return const SizedBox.shrink();
                return Text(_formatAxisAmount(val), style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final p = idx >= 0 && idx < points.length ? points[idx] : null;
                final isRev = spot.barIndex == 0;
                final color = isRev ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                final label = isRev ? 'Revenue' : 'Costs';
                final dateStr = p != null ? '${p.label}: ' : '';

                return LineTooltipItem(
                  '$dateStr$label\n${Helperfunctions.formatDoubleAmountForDisplay(spot.y)}',
                  TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          // 1. Net Revenue Line (Green)
          LineChartBarData(
            spots: revenueSpots,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 14,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: const Color(0xFF10B981)),
            ),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF10B981).withValues(alpha: 0.1)),
          ),
          // 2. Cost Line (Red)
          LineChartBarData(
            spots: costSpots,
            isCurved: true,
            color: const Color(0xFFEF4444),
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 14,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: const Color(0xFFEF4444)),
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  String _formatAxisAmount(double value) {
    if (value >= 1000000) {
      return '₱${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '₱${(value / 1000).toStringAsFixed(0)}k';
    } else {
      return '₱${value.toInt()}';
    }
  }

  Widget _buildBreakdownCard(ColorScheme colorScheme, bool isDark) {
    final isGrossProfitPositive = _data.grossProfit >= 0;
    final isNetProfitPositive = _data.netProfit >= 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF2E3644) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Detailed Profit & Loss Statement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Revenue − COGS − Operating Costs = Net Profit', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // P&L Statement Rows
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 1. REVENUE SECTION
                _buildStatementHeader('1. REVENUE (Delivered Sales)', Icons.trending_up_rounded, colorScheme),
                const SizedBox(height: 8),
                _buildStatementRow(
                  prefix: '(+)',
                  title: 'Gross Delivered Sales',
                  subtitle: '${_data.totalDeliveries} delivered orders',
                  amount: _data.grossRevenue,
                  isBold: false,
                ),
                _buildStatementRow(
                  prefix: '(−)',
                  title: 'Sales Returns & Deductions',
                  subtitle: '${_data.totalItemsReturned} returned units',
                  amount: -_data.returnDeductions,
                  isNegative: true,
                ),
                _buildSubtotalRow(
                  title: 'NET SALES REVENUE',
                  amount: _data.netRevenue,
                  color: isDark ? Colors.white : Colors.black87,
                  isDark: isDark,
                ),
                const SizedBox(height: 18),

                // 2. COGS SECTION
                _buildStatementHeader('2. COST OF GOODS SOLD (COGS)', Icons.inventory_2_outlined, colorScheme),
                const SizedBox(height: 8),
                _buildStatementRow(
                  prefix: '(+)',
                  title: 'Gross Inventory Product Cost',
                  subtitle: 'Item buying price × picked quantity',
                  amount: _data.grossCOGS,
                ),
                _buildStatementRow(
                  prefix: '(−)',
                  title: 'Returned Inventory Cost Deduction',
                  subtitle: 'Item buying price × returned units',
                  amount: -_data.returnCOGSDeductions,
                  isNegative: true,
                ),
                _buildSubtotalRow(title: 'NET COST OF GOODS SOLD', amount: _data.netCOGS, color: const Color(0xFFD97706), isDark: isDark),
                const SizedBox(height: 18),

                // 3. GROSS PROFIT SUBSECTION
                _buildStatementHeader('3. GROSS PROFIT', Icons.account_balance_wallet_outlined, colorScheme),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isGrossProfitPositive
                        ? (isDark ? const Color(0xFF142921) : const Color(0xFFECFDF5))
                        : (isDark ? const Color(0xFF2D1616) : const Color(0xFFFEF2F2)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isGrossProfitPositive
                          ? (isDark ? const Color(0xFF1B4D3E) : const Color(0xFFA7F3D0))
                          : (isDark ? const Color(0xFF5A1D1D) : const Color(0xFFFECACA)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GROSS PROFIT',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isGrossProfitPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                            Text(
                              'Gross Margin: ${_data.grossMarginPercent.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 11, color: isGrossProfitPositive ? const Color(0xFF047857) : const Color(0xFFB91C1C)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Helperfunctions.formatDoubleAmountForDisplay(_data.grossProfit),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isGrossProfitPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. OPERATING COSTS SECTION
                _buildStatementHeader('4. OPERATING COSTS & LOSSES', Icons.money_off_rounded, colorScheme),
                const SizedBox(height: 8),
                _buildStatementRow(
                  prefix: '(−)',
                  title: 'Operating Expenses',
                  subtitle: '${_data.totalExpensesCount} recorded expense entries',
                  amount: -_data.totalExpenses,
                  isNegative: true,
                ),
                _buildStatementRow(
                  prefix: '(−)',
                  title: 'Bad Order Losses (Spoilage & Pullouts)',
                  subtitle: '${_data.totalBadOrdersCount} bad order records',
                  amount: -_data.totalBadOrders,
                  isNegative: true,
                ),
                _buildSubtotalRow(
                  title: 'TOTAL OPERATING DEDUCTIONS',
                  amount: _data.totalOperatingCosts,
                  color: const Color(0xFFEF4444),
                  isDark: isDark,
                ),
                const SizedBox(height: 22),

                // 5. BOTTOM LINE — NET PROFIT BANNER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isNetProfitPositive
                          ? (isDark ? [const Color(0xFF064E3B), const Color(0xFF065F46)] : [const Color(0xFF10B981), const Color(0xFF059669)])
                          : (isDark ? [const Color(0xFF7F1D1D), const Color(0xFF991B1B)] : [const Color(0xFFEF4444), const Color(0xFFDC2626)]),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (isNetProfitPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isNetProfitPositive ? Icons.check_circle_rounded : Icons.warning_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'NET PROFIT (EARNINGS)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Net Margin: ${_data.netMarginPercent.toStringAsFixed(1)}%',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Helperfunctions.formatDoubleAmountForDisplay(_data.netProfit),
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementHeader(String title, IconData icon, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 15, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.3, color: colorScheme.primary),
        ),
      ],
    );
  }

  Widget _buildStatementRow({
    required String prefix,
    required String title,
    required String subtitle,
    required double amount,
    bool isBold = false,
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              prefix,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNegative ? const Color(0xFFEF4444) : Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
                if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Helperfunctions.formatDoubleAmountForDisplay(amount.abs()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isNegative ? const Color(0xFFEF4444) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtotalRow({required String title, required double amount, required Color color, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF141822) : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  child: Text('(=)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Helperfunctions.formatDoubleAmountForDisplay(amount),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeStatsCard(ColorScheme colorScheme, bool isDark) {
    final totalUnits = _data.totalItemsSold + _data.totalItemsReturned;
    final returnRate = totalUnits > 0 ? (_data.totalItemsReturned / totalUnits) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF2E3644) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Volume & Operations Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final chipWidth = constraints.maxWidth < 400 ? (constraints.maxWidth - 10) / 2 : 170.0;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildStatChip(
                    label: 'Delivered Orders',
                    value: '${_data.totalDeliveries}',
                    icon: Icons.local_shipping_outlined,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    label: 'Avg Order Value',
                    value: Helperfunctions.formatDoubleAmountForDisplay(_data.averageOrderValue),
                    icon: Icons.receipt_outlined,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    label: 'Items Sold',
                    value: '${_data.totalItemsSold} pcs',
                    icon: Icons.check_circle_outline_rounded,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    label: 'Items Returned',
                    value: '${_data.totalItemsReturned} pcs (${returnRate.toStringAsFixed(1)}%)',
                    icon: Icons.assignment_return_outlined,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    label: 'Expenses Logged',
                    value: '${_data.totalExpensesCount} entries',
                    icon: Icons.receipt_long_outlined,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    label: 'Bad Order Incidents',
                    value: '${_data.totalBadOrdersCount} pullouts',
                    icon: Icons.assignment_late_outlined,
                    width: chipWidth,
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required IconData icon,
    required double width,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141822) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF28303F) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
