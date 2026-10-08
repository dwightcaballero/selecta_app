import 'package:flutter/material.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/views/pages/dashboard/creditlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/kpi_overview_page.dart';
import 'package:selecta_ops/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjplist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/prospect_scout_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorderlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/configuration_page.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';
import 'package:selecta_ops/views/pages/sidebar/expenselist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistorelist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/inventory_page.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/views/pages/others/settings_page.dart';
import 'package:selecta_ops/views/pages/sidebar/export_reports_page.dart';
import 'package:selecta_ops/views/pages/sidebar/supplier_oos_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlog_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Navigation Drawer for Dashboard containing Operations, KPI shortcuts,
/// Inventory/Settings, and Logout actions.
class DashboardDrawer extends StatelessWidget {
  final Users? currentUser;
  final bool isDealer;
  final bool isSyncing;
  final DashboardDTO dashboardDTO;
  final Stream<int> merchBlitzCountStream;
  final Stream<int> tasksCountStream;
  final Stream<int>? activeReturnsCountStream;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final Future<void> Function(Widget page) onNavigate;

  const DashboardDrawer({
    super.key,
    required this.currentUser,
    required this.isDealer,
    required this.isSyncing,
    required this.dashboardDTO,
    required this.merchBlitzCountStream,
    required this.tasksCountStream,
    this.activeReturnsCountStream,
    required this.onSync,
    required this.onLogout,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Branded Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark ? [const Color(0xFF1E2430), const Color(0xFF141822)] : [colorScheme.primary, colorScheme.primary.withAlpha(210)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: isDark ? const Border(bottom: BorderSide(color: Color(0xFF2E3644), width: 1)) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white.withAlpha(50),
                      child: const Icon(Icons.person_rounded, size: 30, color: Colors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        isDealer ? 'Dealer' : 'Salesman',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  currentUser?.username ?? (isDealer ? 'Dealer' : 'Salesman'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                if (currentUser?.email != null && currentUser!.email.isNotEmpty)
                  Text(currentUser!.email, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12)),
              ],
            ),
          ),

          // 1. Operations
          _buildDrawerSectionHeader(context, 'Operations'),
          StreamBuilder<int>(
            stream: merchBlitzCountStream,
            builder: (context, snapshot) {
              return _buildDrawerItem(context, Icons.campaign_outlined, 'Merch Blitz', const MerchBlitzListPage(), badgeCount: snapshot.data ?? 0);
            },
          ),
          StreamBuilder<int>(
            stream: tasksCountStream,
            builder: (context, snapshot) {
              return _buildDrawerItem(context, Icons.task_alt_outlined, 'Tasks', const TaskListPage(), badgeCount: snapshot.data ?? 0);
            },
          ),
          StreamBuilder<int>(
            stream: activeReturnsCountStream,
            initialData: dashboardDTO.returnedDeliveryCount,
            builder: (ctx, snap) => _buildDrawerItem(
              context,
              Icons.assignment_return_outlined,
              'Returns',
              const ReturnlistPage(),
              badgeCount: snap.data ?? dashboardDTO.returnedDeliveryCount,
            ),
          ),
          _buildDrawerItem(
            context,
            Icons.account_balance_wallet_outlined,
            'Credit List',
            const CreditlistPage(),
            badgeCount: dashboardDTO.unpaidCreditCount,
          ),
          _buildDrawerItem(context, Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
          _buildDrawerItem(context, Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
          _buildDrawerItem(context, Icons.today_outlined, 'End of Day Report', const EndofdayPage()),
          _buildDrawerItem(context, Icons.swap_horiz_outlined, 'Transactions', const TransactionListPage(storeName: '')),
          _buildDrawerItem(context, Icons.file_download_outlined, 'Export Reports (Excel/CSV)', const ExportReportsPage()),
          _buildDrawerItem(context, Icons.insights_rounded, 'KPI & Analytics Hub', KpiOverviewPage(dashboardDTO: dashboardDTO)),

          const Divider(indent: 16, endIndent: 16),

          // 2. Applications
          _buildDrawerSectionHeader(context, 'Applications'),
          _buildDrawerItem(context, Icons.inventory_2_outlined, 'Products', ProductsPage(userRole: 'Dealer')),
          _buildDrawerItem(context, Icons.event_busy_outlined, 'Supplier Out of Stock', const SupplierOosPage()),
          _buildDrawerItem(context, Icons.explore_outlined, 'Prospect Scouting', const ProspectScoutPage()),
          _buildDrawerItem(context, Icons.storefront_outlined, 'Hapi Stores', const HapiStoreListPage()),
          _buildDrawerItem(context, Icons.warehouse_outlined, 'Inventory', const InventoryPage()),
          _buildDrawerItem(context, Icons.map_outlined, 'Journey Plan (PJP)', const PjpListPage(), badgeCount: dashboardDTO.pendingPjpCount),

          const Divider(indent: 16, endIndent: 16),

          // 3. App Settings
          _buildDrawerSectionHeader(context, 'App Settings'),
          _buildDrawerItem(context, Icons.history_outlined, 'Audit Logs', const TransactionLogPage()),
          // Settings hosts Check for Updates & Upload Error Logs; surface update status here.
          ValueListenableBuilder<UpdateDownloadState>(
            valueListenable: AppUpdateService.downloadStateNotifier,
            builder: (context, downloadState, _) {
              Widget? trailing;
              if (downloadState.isReadyToInstall) {
                trailing = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'Update Ready',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                );
              } else if (downloadState.isDownloading) {
                trailing = SizedBox(
                  width: 52,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 6),
                      Text('${(downloadState.progress * 100).toInt()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }
              return _buildDrawerItem(context, Icons.tune_rounded, 'Settings', const SettingsPage(), trailing: trailing);
            },
          ),
          _buildDrawerItem(context, Icons.settings_outlined, 'Configurations', const ConfigurationPage()),

          // 4. Quick Dark Mode Toggle
          ValueListenableBuilder<bool>(
            valueListenable: isDarkModeNotifier,
            builder: (context, isDark, _) {
              return ListTile(
                leading: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 22, color: colorScheme.primary),
                title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
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
          const Divider(indent: 16, endIndent: 16),

          // 5. Logout
          _buildDrawerItem(context, Icons.logout_rounded, 'Logout', null, isLogout: true, onTap: onLogout),

          const SizedBox(height: 8),

          // 6. Current App Version Display
          Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 4),
            child: FutureBuilder(
              future: AppUpdateService.getCurrentPackageInfo(),
              builder: (context, snapshot) {
                final versionText = snapshot.hasData ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}' : '';
                return Center(
                  child: Text(
                    'Selecta Ops $versionText'.trim(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    Widget? nextPage, {
    bool isLogout = false,
    int badgeCount = 0,
    Color? badgeColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : null, size: 22),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: isLogout ? Colors.red : null),
      ),
      trailing:
          trailing ??
          (badgeCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              : null),
      onTap: () async {
        Navigator.pop(context);
        if (onTap != null) {
          onTap();
        } else if (nextPage != null) {
          await onNavigate(nextPage);
        }
      },
    );
  }
}
