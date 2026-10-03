import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/views/pages/dashboard/creditlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/kpi_overview_page.dart';
import 'package:selecta_ops/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjplist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/returnlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorderlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/configuration_page.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';
import 'package:selecta_ops/views/pages/sidebar/expenselist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistorelist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/inventory_page.dart';
import 'package:selecta_ops/views/pages/sidebar/products_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/views/pages/others/settings_page.dart';
import 'package:selecta_ops/views/pages/sidebar/export_reports_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlog_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Permanent left sidebar used on desktop/wide screens.
///
/// Mirrors all items from [DashboardDrawer] but renders as a fixed-width
/// panel (not an overlay) that sits beside the main content area.
///
/// Width: 260dp. Collapses to icon-only rail at [collapsed] = true.
class DashboardSidebar extends StatelessWidget {
  final Users? currentUser;
  final bool isDealer;
  final bool isSyncing;
  final DashboardDTO dashboardDTO;
  final Stream<int> merchBlitzCountStream;
  final Stream<int> tasksCountStream;
  final VoidCallback onSync;
  final VoidCallback onUploadErrorLogs;
  final VoidCallback onLogout;
  final VoidCallback? onCheckForUpdates;
  final Future<void> Function(Widget page) onNavigate;

  static const double kWidth = 260.0;

  const DashboardSidebar({
    super.key,
    required this.currentUser,
    required this.isDealer,
    required this.isSyncing,
    required this.dashboardDTO,
    required this.merchBlitzCountStream,
    required this.tasksCountStream,
    required this.onSync,
    required this.onUploadErrorLogs,
    required this.onLogout,
    this.onCheckForUpdates,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final sidebarBg = isDark ? const Color(0xFF141822) : colorScheme.surface;
    final borderColor = isDark ? const Color(0xFF2E3644) : colorScheme.outlineVariant.withValues(alpha: 0.4);

    return Container(
      width: kWidth,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(
          right: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // ── User Header ─────────────────────────────────────────────────
          _buildHeader(context, isDark, colorScheme),

          // ── Navigation Items ────────────────────────────────────────────
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSection(context, 'Operations'),
                  StreamBuilder<int>(
                    stream: merchBlitzCountStream,
                    builder: (ctx, snap) => _buildItem(ctx, Icons.campaign_outlined, 'Merch Blitz', const MerchBlitzListPage(), badge: snap.data ?? 0),
                  ),
                  StreamBuilder<int>(
                    stream: tasksCountStream,
                    builder: (ctx, snap) => _buildItem(ctx, Icons.task_alt_outlined, 'Tasks', const TaskListPage(), badge: snap.data ?? 0),
                  ),
                  _buildItem(context, Icons.assignment_return_outlined, 'Returns', const ReturnlistPage(), badge: dashboardDTO.returnedDeliveryCount),
                  _buildItem(context, Icons.account_balance_wallet_outlined, 'Credit List', const CreditlistPage(), badge: dashboardDTO.unpaidCreditCount),
                  _buildItem(context, Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
                  _buildItem(context, Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
                  _buildItem(context, Icons.today_outlined, 'End of Day', const EndofdayPage()),
                  _buildItem(context, Icons.swap_horiz_outlined, 'Transactions', const TransactionListPage(storeName: '')),
                  _buildItem(context, Icons.inventory_2_outlined, 'Products', ProductsPage(userRole: isDealer ? 'Dealer' : (currentUser?.role ?? 'Salesman'))),
                  _buildItem(context, Icons.file_download_outlined, 'Export Reports', const ExportReportsPage()),

                  const _SidebarDivider(),

                  _buildSection(context, 'KPI & Analytics'),
                  _buildItem(context, Icons.insights_rounded, 'KPI & Analytics Hub', KpiOverviewPage(dashboardDTO: dashboardDTO)),

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
                      onTap: () { if (!isSyncing) onSync(); },
                    ),
                  ),
                  _buildItem(context, Icons.storefront_outlined, 'Hapi Stores', const HapiStoreListPage()),
                  if (isDealer) _buildItem(context, Icons.warehouse_outlined, 'Inventory', const InventoryPage()),
                  _buildItem(context, Icons.map_outlined, 'Journey Plan (PJP)', const PjpListPage(), badge: dashboardDTO.pendingPjpCount),
                  _buildItem(context, Icons.history_outlined, 'Audit Logs', const TransactionLogPage()),
                  _buildItem(context, Icons.cloud_upload_outlined, 'Upload Error Logs', null, onTap: onUploadErrorLogs),
                  ValueListenableBuilder<UpdateDownloadState>(
                    valueListenable: AppUpdateService.downloadStateNotifier,
                    builder: (context, downloadState, _) {
                      Widget? trailing;
                      if (downloadState.isReadyToInstall) {
                        trailing = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Ready',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      } else if (downloadState.isDownloading) {
                        trailing = Text(
                          '${(downloadState.progress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: Icon(
                          downloadState.isReadyToInstall
                              ? Icons.check_circle_rounded
                              : Icons.system_update_alt_rounded,
                          color: downloadState.isReadyToInstall ? Colors.green : null,
                          size: 20,
                        ),
                        title: const Text('Check for Updates',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: trailing,
                        onTap: () => (onCheckForUpdates ??
                            () => AppUpdateService.checkAndPromptUpdate(context,
                                silent: false, forceRefresh: true))(),
                      );
                    },
                  ),
                  _buildItem(context, Icons.tune_rounded, 'Settings', const SettingsPage()),
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
                    title: const Text('Logout', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red)),
                    onTap: onLogout,
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
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, ColorScheme colorScheme) {
    final displayName = currentUser?.username ?? (isDealer ? 'Dealer' : 'Salesman');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E2430), const Color(0xFF141822)]
              : [colorScheme.primary, colorScheme.primary.withAlpha(210)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: isDark
            ? const Border(bottom: BorderSide(color: Color(0xFF2E3644), width: 1))
            : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white.withAlpha(50),
            child: const Icon(Icons.person_rounded, size: 26, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (currentUser?.email != null && currentUser!.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    currentUser!.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 11),
                  ),
                ],
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isDealer ? 'Dealer' : 'Salesman',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
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
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: badge > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor ?? Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: () async {
        if (onTap != null) {
          onTap();
        } else if (page != null) {
          await onNavigate(page);
        }
      },
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      indent: 16,
      endIndent: 16,
      height: 16,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}
