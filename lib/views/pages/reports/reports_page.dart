import 'package:flutter/material.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/views/pages/dashboard/kpi_overview_page.dart';
import 'package:selecta_ops/views/pages/reports/promo_claims_page.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';
import 'package:selecta_ops/views/pages/sidebar/export_reports_page.dart';
import 'package:selecta_ops/views/pages/sidebar/profit_loss_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlog_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Consolidated Reports & Analytics Hub.
///
/// Houses KPI Analytics, Business Analytics, End of Day Remittances,
/// Supplier Promo Claims, Transaction Ledger, Data Exports, and Audit Logs.
class ReportsPage extends StatelessWidget {
  final DashboardDTO? dashboardDTO;
  final bool isDealer;
  final Stream<int>? unverifiedBreakdownCountStream;

  const ReportsPage({
    super.key,
    this.dashboardDTO,
    this.isDealer = true,
    this.unverifiedBreakdownCountStream,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveDto = dashboardDTO ?? DashboardDTO.empty();

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Reports & Analytics',
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Performance & Analytics ──
            _buildSectionHeader(context, 'PERFORMANCE & ANALYTICS'),
            const SizedBox(height: 8),
            _buildReportCard(
              context,
              title: 'KPI & Analytics Hub',
              subtitle: 'Throughput, Buying%, Scanning%, Drop Size & Target Tracker',
              icon: Icons.insights_rounded,
              iconColor: const Color(0xFF6366F1),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => KpiOverviewPage(dashboardDTO: effectiveDto)),
              ),
            ),
            if (isDealer) ...[
              const SizedBox(height: 10),
              _buildReportCard(
                context,
                title: 'Business Analytics (P&L)',
                subtitle: 'Profit & loss, gross margin, operating expenses & revenue',
                icon: Icons.analytics_outlined,
                iconColor: const Color(0xFF10B981),
                badgeText: 'Dealer',
                badgeColor: const Color(0xFF10B981),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfitLossPage()),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 2. Daily & Field Operations ──
            _buildSectionHeader(context, 'DAILY OPERATIONS & FIELD REPORTS'),
            const SizedBox(height: 8),
            StreamBuilder<int>(
              stream: unverifiedBreakdownCountStream,
              initialData: effectiveDto.unverifiedBreakdownCount,
              builder: (ctx, snap) {
                final count = snap.data ?? effectiveDto.unverifiedBreakdownCount;
                final age = UnverifiedAgeHelper.calculateAgeInDays(effectiveDto.oldestUnverifiedDate);
                final badgeColor = UnverifiedAgeHelper.getBadgeColor(age, Theme.of(ctx).colorScheme);
                final overdueNotice = count > 0 && effectiveDto.oldestUnverifiedDate != null
                    ? ' • ${UnverifiedAgeHelper.getOverdueText(age)}'
                    : '';

                return _buildReportCard(
                  context,
                  title: 'End of Day Report',
                  subtitle: 'Daily salesman collection, remittances & breakdown reconciliation$overdueNotice',
                  icon: Icons.today_outlined,
                  iconColor: const Color(0xFFEA580C),
                  badgeCount: count,
                  badgeColor: badgeColor,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EndofdayPage()),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildReportCard(
              context,
              title: 'Transactions Ledger',
              subtitle: 'Searchable master invoice log & payment receipt slips',
              icon: Icons.receipt_long_outlined,
              iconColor: const Color(0xFF8B5CF6),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransactionListPage(storeName: '')),
              ),
            ),
            if (isDealer) ...[
              const SizedBox(height: 10),
              _buildReportCard(
                context,
                title: 'Supplier Promo Claims',
                subtitle: 'Retailer discount claims & supplier reimbursements',
                icon: Icons.request_quote_outlined,
                iconColor: const Color(0xFF0284C7),
                badgeText: 'Dealer',
                badgeColor: const Color(0xFF0284C7),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PromoClaimsPage()),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 3. Data Export & System Logs ──
            _buildSectionHeader(context, 'DATA EXPORT & AUDIT TRAIL'),
            const SizedBox(height: 8),
            _buildReportCard(
              context,
              title: 'Export Reports (Excel/CSV)',
              subtitle: 'Download spreadsheets for Sales, Deliveries, Inventory & Stores',
              icon: Icons.file_download_outlined,
              iconColor: const Color(0xFF0D9488),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExportReportsPage()),
              ),
            ),
            const SizedBox(height: 10),
            _buildReportCard(
              context,
              title: 'Audit Logs',
              subtitle: 'System change history, operational audit trail & timestamps',
              icon: Icons.history_outlined,
              iconColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransactionLogPage()),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildReportCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    String? badgeText,
    Color? badgeColor,
    int? badgeCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.cardTheme.color ?? (isDark ? const Color(0xFF1E2430) : Colors.white),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? colorScheme.primary).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeColor ?? colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                        if (badgeCount != null && badgeCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor ?? Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$badgeCount',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
