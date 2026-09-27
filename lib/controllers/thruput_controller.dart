import 'package:flutter_app/dto/dashboard_dto.dart';

/// Computed KPI throughput metrics.
class ThruputMetrics {
  final double safeThruput;
  final int totalStores;
  final double conversionRate;
  final double averageSale;
  final double averageTransactions;
  final double remainingThruput;
  final double progress;
  final bool isOnTarget;
  final double surplus;

  const ThruputMetrics({
    required this.safeThruput,
    required this.totalStores,
    required this.conversionRate,
    required this.averageSale,
    required this.averageTransactions,
    required this.remainingThruput,
    required this.progress,
    required this.isOnTarget,
    required this.surplus,
  });
}

/// Controller responsible for throughput KPI calculations and metric breakdowns.
class ThruputController {
  static const double targetThruput = 8000.0;

  /// Calculates all derived throughput metrics safely from a given [DashboardDTO].
  ThruputMetrics calculateMetrics(DashboardDTO dashboardDTO) {
    // Prevent NaN if buyingCount is 0
    final safeThruput = dashboardDTO.buyingThruput.isNaN ? 0.0 : dashboardDTO.buyingThruput;
    final totalStores = dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount;
    final conversionRate = totalStores == 0 ? 0.0 : (dashboardDTO.buyingCount / totalStores * 100);

    final averageSale = dashboardDTO.totaltransactionCount == 0
        ? 0.0
        : dashboardDTO.totalBuyingSales / dashboardDTO.totaltransactionCount;
    final averageTransactions = dashboardDTO.buyingCount == 0
        ? 0.0
        : dashboardDTO.totaltransactionCount / dashboardDTO.buyingCount;

    final remainingThruput = (targetThruput - safeThruput).clamp(0.0, targetThruput);
    final progress = (targetThruput == 0 ? 0.0 : (safeThruput / targetThruput)).clamp(0.0, 1.0);
    final isOnTarget = safeThruput >= targetThruput;
    final surplus = (safeThruput - targetThruput).clamp(0.0, double.infinity);

    return ThruputMetrics(
      safeThruput: safeThruput,
      totalStores: totalStores,
      conversionRate: conversionRate,
      averageSale: averageSale,
      averageTransactions: averageTransactions,
      remainingThruput: remainingThruput,
      progress: progress,
      isOnTarget: isOnTarget,
      surplus: surplus,
    );
  }
}
