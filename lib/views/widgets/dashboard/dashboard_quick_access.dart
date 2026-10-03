import 'package:flutter/material.dart';
import 'package:selecta_ops/data/responsive.dart';
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

    // Gather all 6 card definitions in order
    final cards = [
      _CardDef(label: 'Book Order', icon: Icons.add_shopping_cart_rounded, nextPage: const BookOrderPage()),
      _CardDef(label: 'Picklists', icon: Icons.fact_check_outlined, nextPage: const PicklistListPage(), count: dashboardDTO.pendingPicklistCount, stream: pendingPicklistsCountStream),
      _CardDef(label: 'Deliveries', icon: Icons.local_shipping_outlined, nextPage: const DeliveryListPage(), count: dashboardDTO.pendingDeliveryCount),
      _CardDef(label: 'Purchase Orders', icon: Icons.assignment_outlined, nextPage: const PurchaseorderlistPage(), stream: purchaseOrdersAwaitingCountStream),
      _CardDef(label: 'Credit', icon: Icons.credit_card_outlined, nextPage: const CreditlistPage(), count: dashboardDTO.unpaidCreditCount),
      _CardDef(label: 'Returns', icon: Icons.assignment_return_outlined, nextPage: const ReturnlistPage(), count: dashboardDTO.returnedDeliveryCount),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Adaptive column count: scales with available width
        final w = constraints.maxWidth;
        final cols = w < 360 ? 2
            : w < 520 ? 3
            : w < 700 ? 4
            : w < 900 ? 5
            : 6;

        // Scale icon and font sizes for larger screens
        final iconSize = ScreenSize.isDesktop(context) ? 30.0
            : ScreenSize.isTablet(context) ? 28.0 : 26.0;
        final fontSize = ScreenSize.isDesktop(context) ? 13.5
            : ScreenSize.isTablet(context) ? 13.0 : 13.0;

        return GridView.count(
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.95,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards.map((def) {
            return def.stream != null
                ? StreamBuilder<int>(
                    stream: def.stream,
                    initialData: def.count,
                    builder: (ctx, snap) => _buildCard(
                      ctx,
                      label: def.label,
                      icon: def.icon,
                      count: snap.data ?? 0,
                      color: primaryColor,
                      nextPage: def.nextPage,
                      iconSize: iconSize,
                      fontSize: fontSize,
                    ),
                  )
                : _buildCard(
                    context,
                    label: def.label,
                    icon: def.icon,
                    count: def.count,
                    color: primaryColor,
                    nextPage: def.nextPage,
                    iconSize: iconSize,
                    fontSize: fontSize,
                  );
          }).toList(),
        );
      },
    );
  }


  Widget _buildCard(
    BuildContext context, {
    required String label,
    required IconData icon,
    int count = 0,
    required Color color,
    required Widget nextPage,
    double iconSize = 26,
    double fontSize = 13,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: isDark ? 2 : 1.5,
      shadowColor: Colors.black.withAlpha(isDark ? 50 : 20),
      color: theme.cardTheme.color ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withAlpha(90),
          width: isDark ? 1.2 : 1.1,
        ),
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
                isLabelVisible: count > 0,
                label: Text(
                  '$count',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                backgroundColor: Colors.red,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 40 : 25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: color),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data holder for quick-access card definitions.
class _CardDef {
  final String label;
  final IconData icon;
  final Widget nextPage;
  final int count;
  final Stream<int>? stream;

  const _CardDef({
    required this.label,
    required this.icon,
    required this.nextPage,
    this.count = 0,
    this.stream,
  });
}
