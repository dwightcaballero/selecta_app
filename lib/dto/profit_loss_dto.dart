class ProfitLossTrendPoint {
  final DateTime date;
  final String label;
  final double revenue;
  final double cogs;
  final double expenses;
  final double badOrders;
  final double cost; // cogs + expenses + badOrders
  final double profit; // revenue - cost
  final int deliveryCount;

  const ProfitLossTrendPoint({
    required this.date,
    required this.label,
    required this.revenue,
    this.cogs = 0.0,
    this.expenses = 0.0,
    this.badOrders = 0.0,
    required this.cost,
    required this.profit,
    this.deliveryCount = 0,
  });
}

/// Data Transfer Object representing computed Profit & Loss analytics
/// for a selected time period.
class ProfitLossDTO {
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodLabel;

  // Revenue metrics
  final double grossRevenue;
  final double returnDeductions;
  final double netRevenue;

  // Cost of Goods Sold (COGS) metrics
  final double grossCOGS;
  final double returnCOGSDeductions;
  final double netCOGS;

  // Gross Profit
  final double grossProfit;
  final double grossMarginPercent;

  // Operating Costs
  final double totalExpenses;
  final double totalBadOrders;
  final double totalOperatingCosts;

  // Net Profit
  final double netProfit;
  final double netMarginPercent;

  // Volume & Counts
  final int totalDeliveries;
  final int totalItemsSold;
  final int totalItemsReturned;
  final int totalExpensesCount;
  final int totalBadOrdersCount;
  final double averageOrderValue;

  // Trend data points for visualization
  final List<ProfitLossTrendPoint> trendPoints;

  const ProfitLossDTO({
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    required this.grossRevenue,
    required this.returnDeductions,
    required this.netRevenue,
    required this.grossCOGS,
    required this.returnCOGSDeductions,
    required this.netCOGS,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.totalExpenses,
    required this.totalBadOrders,
    required this.totalOperatingCosts,
    required this.netProfit,
    required this.netMarginPercent,
    required this.totalDeliveries,
    required this.totalItemsSold,
    required this.totalItemsReturned,
    required this.totalExpensesCount,
    required this.totalBadOrdersCount,
    required this.averageOrderValue,
    required this.trendPoints,
  });

  static ProfitLossDTO empty({DateTime? start, DateTime? end, String label = ''}) {
    final now = DateTime.now();
    final s = start ?? DateTime(now.year, now.month, 1);
    final e = end ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return ProfitLossDTO(
      periodStart: s,
      periodEnd: e,
      periodLabel: label,
      grossRevenue: 0.0,
      returnDeductions: 0.0,
      netRevenue: 0.0,
      grossCOGS: 0.0,
      returnCOGSDeductions: 0.0,
      netCOGS: 0.0,
      grossProfit: 0.0,
      grossMarginPercent: 0.0,
      totalExpenses: 0.0,
      totalBadOrders: 0.0,
      totalOperatingCosts: 0.0,
      netProfit: 0.0,
      netMarginPercent: 0.0,
      totalDeliveries: 0,
      totalItemsSold: 0,
      totalItemsReturned: 0,
      totalExpensesCount: 0,
      totalBadOrdersCount: 0,
      averageOrderValue: 0.0,
      trendPoints: const [],
    );
  }
}
