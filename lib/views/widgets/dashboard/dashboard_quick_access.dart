import 'package:flutter/material.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/creditlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/deliverylist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_list_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorderlist_page.dart';

/// Operational 2x3 quick action cards grid for core workflow entry points:
/// Book Order, Picklists, Deliveries, Purchase Orders, Credit, and Returns.
class DashboardQuickAccessGrid extends StatelessWidget {
  final DashboardDTO dashboardDTO;
  final Stream<int>? pendingPicklistsCountStream;
  final Stream<int>? purchaseOrdersAwaitingCountStream;
  final Future<void> Function(Widget page) onNavigate;

  const DashboardQuickAccessGrid({
    super.key,
    required this.dashboardDTO,
    required this.pendingPicklistsCountStream,
    required this.purchaseOrdersAwaitingCountStream,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Row(
          children: [
            _buildCard(
              context,
              label: 'Store Order',
              subtitle: 'Sell to store',
              icon: Icons.storefront_outlined,
              color: primaryColor,
              nextPage: const BookOrderPage(),
            ),
            const SizedBox(width: 10),
            _buildCard(
              context,
              label: 'Credit',
              icon: Icons.credit_card_outlined,
              count: dashboardDTO.unpaidCreditCount,
              color: primaryColor,
              nextPage: const CreditlistPage(),
            ),
            const SizedBox(width: 10),
            _buildCard(
              context,
              label: 'Returns',
              icon: Icons.assignment_return_outlined,
              count: dashboardDTO.returnedDeliveryCount,
              color: primaryColor,
              nextPage: const ReturnlistPage(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String label,
    String? subtitle,
    required IconData icon,
    int count = 0,
    Stream<int>? stream,
    required Color color,
    required Widget nextPage,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    Widget cardContent(int badgeCount) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: isDark ? 2 : 1.5,
        shadowColor: Colors.black.withAlpha(isDark ? 50 : 20),
        color: theme.cardTheme.color ?? Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withAlpha(90), width: isDark ? 1.2 : 1.1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onNavigate(nextPage),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badgeCount > 0,
                  label: Text('$badgeCount', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  backgroundColor: Colors.red,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(color: color.withAlpha(isDark ? 40 : 25), shape: BoxShape.circle),
                    child: Icon(icon, size: 26, color: color),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: subtitle != null ? 12.5 : 13, height: 1.15),
                          textAlign: TextAlign.center,
                          maxLines: subtitle != null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1.5),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant, height: 1.1),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: stream != null
          ? StreamBuilder<int>(stream: stream, initialData: count, builder: (context, snapshot) => cardContent(snapshot.data ?? 0))
          : cardContent(count),
    );
  }
}
