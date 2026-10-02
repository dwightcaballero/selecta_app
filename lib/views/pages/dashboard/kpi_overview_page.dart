import 'package:flutter/material.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/views/pages/dashboard/analytics_page.dart';
import 'package:selecta_ops/views/pages/dashboard/buyinglist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/expansion_page.dart';
import 'package:selecta_ops/views/pages/dashboard/placementlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/sales_page.dart';
import 'package:selecta_ops/views/pages/dashboard/scanninglist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/thruput_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Consolidated KPI & Analytics Hub providing a unified, tabbed view for
/// Trends, Sales, Buying Stores, Throughput, Placement, Scanning, and Expansion.
///
/// This consolidates 7 previously separate drawer items into a single, cohesive hub.
class KpiOverviewPage extends StatefulWidget {
  final DashboardDTO? dashboardDTO;
  final int initialIndex;

  const KpiOverviewPage({
    super.key,
    this.dashboardDTO,
    this.initialIndex = 0,
  });

  @override
  State<KpiOverviewPage> createState() => _KpiOverviewPageState();
}

class _KpiOverviewPageState extends State<KpiOverviewPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<_KpiTabMeta> _tabs = [
    _KpiTabMeta(label: 'Trends', icon: Icons.insights_rounded),
    _KpiTabMeta(label: 'Sales', icon: Icons.attach_money_rounded),
    _KpiTabMeta(label: 'Buying Stores', icon: Icons.shopping_cart_outlined),
    _KpiTabMeta(label: 'Throughput', icon: Icons.speed_outlined),
    _KpiTabMeta(label: 'Placement', icon: Icons.grid_view_outlined),
    _KpiTabMeta(label: 'Scanning', icon: Icons.qr_code_scanner_outlined),
    _KpiTabMeta(label: 'Expansion', icon: Icons.trending_up_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final safeIndex = widget.initialIndex.clamp(0, _tabs.length - 1);
    _tabController = TabController(length: _tabs.length, vsync: this, initialIndex: safeIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'KPI & Analytics Hub',
        subtitle: 'Performance metrics, trends & store coverage',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: isDark ? const Color(0xFF1E2430) : theme.colorScheme.primary,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: isDark ? colorScheme.primary : Colors.white,
              indicatorWeight: 3,
              labelColor: isDark ? colorScheme.primary : Colors.white,
              unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : Colors.white.withValues(alpha: 0.72),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: _tabs
                  .map(
                    (tab) => Tab(
                      icon: Icon(tab.icon, size: 18),
                      text: tab.label,
                      iconMargin: const EdgeInsets.only(bottom: 2),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const AnalyticsPage(showAppBar: false),
          const SalesPage(showAppBar: false),
          const BuyinglistPage(showAppBar: false),
          ThruputPage(
            dashboardDTO: widget.dashboardDTO ?? DashboardDTO.empty(),
            showAppBar: false,
          ),
          const PlacementlistPage(showAppBar: false),
          const ScanninglistPage(showAppBar: false),
          const ExpansionPage(showAppBar: false),
        ],
      ),
    );
  }
}

class _KpiTabMeta {
  final String label;
  final IconData icon;

  const _KpiTabMeta({required this.label, required this.icon});
}
