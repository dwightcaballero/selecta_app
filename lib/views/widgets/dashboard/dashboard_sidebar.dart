import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/views/pages/dashboard/creditlist_page.dart';
import 'package:selecta_ops/views/pages/reports/reports_page.dart';
import 'package:selecta_ops/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjplist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/prospect_scout_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/van_load_page.dart';
import 'package:selecta_ops/views/pages/dashboard/van_sell_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorderlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/configuration_page.dart';
import 'package:selecta_ops/views/pages/sidebar/expenselist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistorelist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/inventory_page.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/views/pages/others/settings_page.dart';
import 'package:selecta_ops/views/pages/sidebar/supplier_oos_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Permanent left sidebar used on desktop/wide screens.
///
/// Mirrors all items from [DashboardDrawer] but renders as a fixed-width
/// panel (not an overlay) that sits beside the main content area.
///
/// Width: 260dp. Collapses to icon-only rail at [collapsed] = true.
class DashboardSidebar extends StatefulWidget {
  final Users? currentUser;
  final bool isDealer;
  final bool isSyncing;
  final DashboardDTO dashboardDTO;
  final Stream<int> merchBlitzCountStream;
  final Stream<int> tasksCountStream;
  final Stream<int>? activeReturnsCountStream;
  final Stream<int>? unverifiedBreakdownCountStream;
  final int? currentTabIndex;
  final ValueChanged<int>? onTabSelected;
  final Stream<int>? purchaseOrdersAwaitingCountStream;
  final Stream<int>? pendingPicklistsCountStream;
  final Stream<int>? pendingDeliveriesCountStream;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final Future<void> Function(Widget page) onNavigate;
  final VoidCallback? onCollapse;

  static const double kWidth = 260.0;

  const DashboardSidebar({
    super.key,
    required this.currentUser,
    required this.isDealer,
    required this.isSyncing,
    required this.dashboardDTO,
    required this.merchBlitzCountStream,
    required this.tasksCountStream,
    this.activeReturnsCountStream,
    this.unverifiedBreakdownCountStream,
    this.currentTabIndex,
    this.onTabSelected,
    this.purchaseOrdersAwaitingCountStream,
    this.pendingPicklistsCountStream,
    this.pendingDeliveriesCountStream,
    required this.onSync,
    required this.onLogout,
    required this.onNavigate,
    this.onCollapse,
  });

  @override
  State<DashboardSidebar> createState() => _DashboardSidebarState();
}

class _DashboardSidebarState extends State<DashboardSidebar> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final sidebarBg = isDark ? const Color(0xFF141822) : colorScheme.surface;
    final borderColor = isDark ? const Color(0xFF2E3644) : colorScheme.outlineVariant.withValues(alpha: 0.4);

    return Container(
      width: DashboardSidebar.kWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: borderColor, width: 1)),
      ),
      child: Material(
        color: sidebarBg,
        child: Column(
          children: [
            // ── User Header ─────────────────────────────────────────────────
            _buildHeader(context, isDark, colorScheme),

            // ── Navigation Items ────────────────────────────────────────────
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView(
                  controller: _scrollController,
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // ── Main Navigation Tabs (Unified) ───────────────────────────
                    if (widget.currentTabIndex != null && widget.onTabSelected != null) ...[
                      _buildSection(context, 'Main Navigation'),
                      _buildNavTabItem(context, icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, title: 'Home', tabIndex: 0),
                      StreamBuilder<int>(
                        stream: widget.purchaseOrdersAwaitingCountStream,
                        initialData: 0,
                        builder: (ctx, snap) => _buildNavTabItem(
                          ctx,
                          icon: Icons.inventory_2_outlined,
                          selectedIcon: Icons.inventory_2_rounded,
                          title: 'Restock',
                          tabIndex: 1,
                          badge: snap.data ?? 0,
                        ),
                      ),
                      _buildNavTabItem(
                        context,
                        icon: Icons.warehouse_outlined,
                        selectedIcon: Icons.warehouse_rounded,
                        title: 'Inventory',
                        tabIndex: 2,
                      ),
                      StreamBuilder<int>(
                        stream: widget.pendingPicklistsCountStream,
                        initialData: widget.dashboardDTO.pendingPicklistCount,
                        builder: (ctx, snap) => _buildNavTabItem(
                          ctx,
                          icon: Icons.fact_check_outlined,
                          selectedIcon: Icons.fact_check_rounded,
                          title: 'PickLists',
                          tabIndex: 3,
                          badge: snap.data ?? widget.dashboardDTO.pendingPicklistCount,
                        ),
                      ),
                      StreamBuilder<int>(
                        stream: widget.pendingDeliveriesCountStream,
                        initialData: widget.dashboardDTO.pendingDeliveryCount,
                        builder: (ctx, snap) => _buildNavTabItem(
                          ctx,
                          icon: Icons.local_shipping_outlined,
                          selectedIcon: Icons.local_shipping_rounded,
                          title: 'Deliveries',
                          tabIndex: 4,
                          badge: snap.data ?? widget.dashboardDTO.pendingDeliveryCount,
                        ),
                      ),
                      const _SidebarDivider(),
                    ],

                    _buildSection(context, 'Operations'),
                    StreamBuilder<int>(
                      stream: widget.merchBlitzCountStream,
                      builder: (ctx, snap) =>
                          _buildItem(ctx, Icons.campaign_outlined, 'Merch Blitz', const MerchBlitzListPage(), badge: snap.data ?? 0),
                    ),
                    StreamBuilder<int>(
                      stream: widget.tasksCountStream,
                      builder: (ctx, snap) => _buildItem(ctx, Icons.task_alt_outlined, 'Tasks', const TaskListPage(), badge: snap.data ?? 0),
                    ),
                    StreamBuilder<int>(
                      stream: widget.activeReturnsCountStream,
                      initialData: widget.dashboardDTO.returnedDeliveryCount,
                      builder: (ctx, snap) => _buildItem(
                        ctx,
                        Icons.assignment_return_outlined,
                        'Returns',
                        const ReturnlistPage(),
                        badge: snap.data ?? widget.dashboardDTO.returnedDeliveryCount,
                      ),
                    ),
                    _buildItem(
                      context,
                      Icons.account_balance_wallet_outlined,
                      'Credit List',
                      const CreditlistPage(),
                      badge: widget.dashboardDTO.unpaidCreditCount,
                    ),
                    _buildItem(context, Icons.local_shipping_outlined, 'Van Load', const VanLoadPage()),
                    _buildItem(context, Icons.directions_car_filled_outlined, 'Van Sell', const VanSellPage()),
                    _buildItem(context, Icons.explore_outlined, 'Prospect Scouting', const ProspectScoutPage()),
                    _buildItem(context, Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
                    _buildItem(context, Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
                    _buildItem(
                      context,
                      Icons.inventory_2_outlined,
                      'Products',
                      ProductsPage(userRole: widget.currentUser?.role ?? (widget.isDealer ? 'Dealer' : 'Salesman')),
                    ),
                    StreamBuilder<int>(
                      stream: widget.unverifiedBreakdownCountStream,
                      initialData: widget.dashboardDTO.unverifiedBreakdownCount,
                      builder: (ctx, snap) {
                        final count = snap.data ?? widget.dashboardDTO.unverifiedBreakdownCount;
                        final age = UnverifiedAgeHelper.calculateAgeInDays(widget.dashboardDTO.oldestUnverifiedDate);
                        final badgeColor = UnverifiedAgeHelper.getBadgeColor(age, Theme.of(ctx).colorScheme);
                        final tooltip = count > 0 && widget.dashboardDTO.oldestUnverifiedDate != null
                            ? 'Unverified reports backlog: ${UnverifiedAgeHelper.getOverdueText(age)}'
                            : null;

                        return _buildItem(
                          ctx,
                          Icons.bar_chart_rounded,
                          'Reports',
                          ReportsPage(
                            dashboardDTO: widget.dashboardDTO,
                            isDealer: widget.isDealer,
                            unverifiedBreakdownCountStream: widget.unverifiedBreakdownCountStream,
                          ),
                          badge: count,
                          badgeColor: badgeColor,
                          badgeTooltip: tooltip,
                        );
                      },
                    ),

                    const _SidebarDivider(),

                    _buildSection(context, 'Settings'),
                    ValueListenableBuilder<int>(
                      valueListenable: OfflineSyncService.instance.pendingCountNotifier,
                      builder: (ctx, count, _) => _buildItem(
                        ctx,
                        Icons.sync_rounded,
                        'Sync Data',
                        null,
                        badge: count,
                        badgeColor: Colors.amber.shade800,
                        onTap: () {
                          if (!widget.isSyncing) widget.onSync();
                        },
                      ),
                    ),
                    _buildItem(context, Icons.storefront_outlined, 'Hapi Stores', const HapiStoreListPage()),
                    if (widget.isDealer) _buildItem(context, Icons.event_busy_outlined, 'Supplier Out of Stock', const SupplierOosPage()),
                    if (widget.isDealer) _buildItem(context, Icons.warehouse_outlined, 'Inventory', const InventoryPage()),
                    _buildItem(context, Icons.map_outlined, 'Journey Plan (PJP)', const PjpListPage(), badge: widget.dashboardDTO.pendingPjpCount),
                    // Settings hosts Check for Updates & Upload Error Logs; surface update status here.
                    ValueListenableBuilder<UpdateDownloadState>(
                      valueListenable: AppUpdateService.downloadStateNotifier,
                      builder: (ctx, downloadState, _) {
                        Widget? trailing;
                        if (downloadState.isReadyToInstall) {
                          trailing = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(8)),
                            child: const Text(
                              'Update Ready',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          );
                        } else if (downloadState.isDownloading) {
                          trailing = Text(
                            '${(downloadState.progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          );
                        }
                        return _buildItem(ctx, Icons.tune_rounded, 'Settings', const SettingsPage(), trailing: trailing);
                      },
                    ),
                    _buildItem(context, Icons.settings_outlined, 'Configurations', const ConfigurationPage()),

                    const _SidebarDivider(),

                    // Dark mode toggle
                    ValueListenableBuilder<bool>(
                      valueListenable: isDarkModeNotifier,
                      builder: (ctx, isDark, _) {
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 20),
                          title: const Text('Dark Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          trailing: Switch.adaptive(
                            value: isDark,
                            onChanged: (val) async {
                              isDarkModeNotifier.value = val;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool(KConstants.themeModeKey, val);
                            },
                          ),
                        );
                      },
                    ),

                    // Logout
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.logout_rounded, size: 20, color: Colors.red),
                      title: const Text(
                        'Logout',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red),
                      ),
                      onTap: widget.onLogout,
                    ),

                    const SizedBox(height: 12),

                    // Version
                    FutureBuilder(
                      future: AppUpdateService.getCurrentPackageInfo(),
                      builder: (ctx, snap) {
                        final ver = snap.hasData ? 'v${snap.data!.version}+${snap.data!.buildNumber}' : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Center(
                            child: Text(
                              'Selecta Ops $ver'.trim(),
                              style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, ColorScheme colorScheme) {
    final displayName = widget.currentUser?.username ?? (widget.isDealer ? 'Dealer' : 'Salesman');
    final topPadding = MediaQuery.paddingOf(context).top;
    const toolbarHeight = 72.0;
    final totalHeight = topPadding + toolbarHeight;

    final appbarBg = isDark ? const Color(0xFF1E2430) : colorScheme.primary;
    final bottomBorderColor = isDark ? const Color(0xFF2E3644) : colorScheme.primary.withAlpha(220);

    return Container(
      height: totalHeight,
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 0),
      decoration: BoxDecoration(
        color: appbarBg,
        border: Border(bottom: BorderSide(color: bottomBorderColor, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: Colors.white.withAlpha(50),
            child: const Icon(Icons.person_rounded, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        widget.currentUser?.role ?? (widget.isDealer ? 'Dealer' : 'Salesman'),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onCollapse != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.menu_open_rounded, color: Colors.white, size: 22),
              tooltip: 'Collapse sidebar (Focus Mode)',
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: widget.onCollapse,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildNavTabItem(
    BuildContext context, {
    required IconData icon,
    required IconData selectedIcon,
    required String title,
    required int tabIndex,
    int badge = 0,
    Color? badgeColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = widget.currentTabIndex == tabIndex;

    final selectedBg = isSelected ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent;
    final itemColor = isSelected ? colorScheme.primary : colorScheme.onSurface;
    final iconColor = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selectedBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onTabSelected?.call(tabIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(isSelected ? selectedIcon : icon, size: 21, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: itemColor),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    Widget? page, {
    int badge = 0,
    Color? badgeColor,
    String? badgeTooltip,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeWidget = badge > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '$badge',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          )
        : null;

    final effectiveTrailing = trailing ??
        (badgeWidget != null
            ? (badgeTooltip != null ? Tooltip(message: badgeTooltip, child: badgeWidget) : badgeWidget)
            : null);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: effectiveTrailing,
      onTap: () async {
        if (onTap != null) {
          onTap();
        } else if (page != null) {
          await widget.onNavigate(page);
        }
      },
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(indent: 16, endIndent: 16, height: 16, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5));
  }
}
