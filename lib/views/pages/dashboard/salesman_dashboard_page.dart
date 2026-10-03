import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/deliverylist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/kpi_overview_page.dart';
import 'package:selecta_ops/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_list_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjplist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/placementlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/scanninglist_page.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorderlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';
import 'package:selecta_ops/views/pages/sidebar/expenselist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlist_page.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/pages/sidebar/superadmin_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/services/app_update_service.dart';

class SalesmanDashboardPage extends StatefulWidget {
  const SalesmanDashboardPage({super.key});

  @override
  State<SalesmanDashboardPage> createState() => _SalesmanDashboardPageState();
}

class _SalesmanDashboardPageState extends State<SalesmanDashboardPage> {
  // Controller managing data syncing, live count streams, role switching, and user state
  final DashboardController _controller = DashboardController();

  late final Stream<int> _tasksCountStream;
  late final Stream<int> _merchBlitzCountStream;
  late final Stream<int> _pendingPicklistsCountStream;
  late final Stream<int> _pendingDeliveriesCountStream;
  Users? _currentUser;
  DashboardDTO _dashboardDTO = DashboardDTO.empty();
  bool _isLoading = true;
  bool _isSyncing = false;
  String _lastSyncDateTime = '';
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tasksCountStream = _controller.getTasksPendingAndOverdueCountStream();
    _merchBlitzCountStream = _controller.getMerchBlitzCountStream();
    _pendingPicklistsCountStream = _controller.getPendingPicklistsCountStream();
    _pendingDeliveriesCountStream = _controller.getPendingDeliveriesCountStream();
    _loadInitialData();
  }

  // Load cached dashboard metrics and user data via DashboardController
  Future<void> _loadInitialData() async {
    try {
      final user = await _controller.getCurrentUser();
      final lastSync = await DashboardController.getLastSync();
      final dto = await _controller.getCachedDashboardData() ?? DashboardDTO.empty();

      if (mounted) {
        setState(() {
          _currentUser = user;
          _lastSyncDateTime = lastSync;
          _dashboardDTO = dto;
          _isLoading = false;
        });
        AppUpdateService.checkAndPromptUpdate(context, silent: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Fetch fresh metrics and recalculate dashboard totals
  Future<void> _syncDashboard() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final latestDto = await DashboardController.getLatestDashboardData();
      final lastSync = await DashboardController.getLastSync();

      if (mounted) {
        setState(() {
          _dashboardDTO = latestDto;
          _lastSyncDateTime = lastSync;
        });
        ShowMessage.success(context, 'Salesman dashboard synced successfully.');
      }
    } catch (e, s) {
      ErrorLogService.logError(page: 'SalesmanDashboardPage', action: 'Sync Salesman Dashboard', error: e, stackTrace: s);
      if (mounted) {
        ShowMessage.error(context, 'Sync failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // Log out through DashboardController
  Future<void> _onLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, color: colorScheme.error),
              const SizedBox(width: 10),
              const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text('Are you sure you want to sign out of your salesman account?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await _controller.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error signing out.');
        }
      }
    }
  }

  Future<void> _showSecretRoleSwitchDialog() async {
    final passwordController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Super Admin Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter superadmin password to access developer controls & AI settings:',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Verify & Open')),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (passwordController.text.trim() != '123') {
      if (mounted) {
        ShowMessage.error(context, 'Incorrect admin password.');
      }
      return;
    }

    if (mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SuperAdminPage()));
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        await _syncDashboard();
      }
    }
  }

  int _secretTapCount = 0;
  DateTime? _lastSecretTapTime;

  void _onWelcomeBannerTap() {
    final now = DateTime.now();
    if (_lastSecretTapTime != null && now.difference(_lastSecretTapTime!) > const Duration(seconds: 2)) {
      _secretTapCount = 0;
    }
    _lastSecretTapTime = now;
    _secretTapCount++;

    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      _showSecretRoleSwitchDialog();
    }
  }

  Widget _buildWelcomeBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = _currentUser?.username ?? 'Salesman';
    final hasSyncTime = _lastSyncDateTime.isNotEmpty && _lastSyncDateTime != 'Never';

    return GestureDetector(
      onTap: _onWelcomeBannerTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colorScheme.tertiary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.badge_outlined, color: colorScheme.tertiary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Welcome, $displayName!',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: colorScheme.tertiary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Salesman',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.tertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.sync_rounded, size: 15, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hasSyncTime ? 'Last synced: $_lastSyncDateTime' : 'Not synced yet',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildQuickAccessCard({
    required String label,
    required IconData icon,
    Widget? nextPage,
    VoidCallback? onTap,
    int count = 0,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = iconColor ?? colorScheme.primary;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (onTap != null) {
            onTap();
          } else if (nextPage != null) {
            await Helperfunctions.navigateThenWait(context, nextPage);
            if (mounted) {
              final cached = await _controller.getCachedDashboardData();
              if (cached != null) {
                setState(() {
                  _dashboardDTO = cached;
                });
              }
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: count > 0,
                label: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                backgroundColor: colorScheme.error,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: effectiveColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 26, color: effectiveColor),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
            decoration: BoxDecoration(color: colorScheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, size: 32, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  _currentUser?.username ?? 'Salesman',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(_currentUser?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),

          // Drawer Navigation Items (Field Activities & Reports)
          _buildDrawerItem(Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
          _buildDrawerItem(Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
          _buildDrawerItem(Icons.swap_horiz_outlined, 'Transactions', const TransactionListPage(storeName: '')),
          _buildDrawerItem(Icons.insights_rounded, 'KPI & Analytics Hub', KpiOverviewPage(dashboardDTO: _dashboardDTO)),
          _buildDrawerItem(Icons.cloud_upload_outlined, 'Upload Error Logs', null, onTap: _handleUploadErrorLogs),
          _buildDrawerItem(
            Icons.system_update_alt_rounded,
            'Check for Updates',
            null,
            onTap: () {
              AppUpdateService.checkAndPromptUpdate(context, silent: false, forceRefresh: true);
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          _buildDrawerItem(Icons.logout_rounded, 'Sign Out', null, isLogout: true),

          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 4),
            child: FutureBuilder(
              future: AppUpdateService.getCurrentPackageInfo(),
              builder: (context, snapshot) {
                final versionText = snapshot.hasData ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}' : '';
                return Center(
                  child: Text(
                    'Selecta Ops $versionText'.trim(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUploadErrorLogs() async {
    final pendingCount = await ErrorLogService.getPendingLogCount();
    if (!mounted) return;

    if (pendingCount == 0) {
      await ShowMessage.alert(
        context,
        title: 'Error Logs',
        message: 'All error logs are already synced or no errors recorded.',
        icon: Icons.check_circle_outline,
      );
      return;
    }

    await Helperfunctions.showLoading(context: context, showLoading: true);
    try {
      final count = await ErrorLogService.uploadPendingLogs();
      if (!mounted) return;
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.success(context, 'Successfully uploaded $count error log${count == 1 ? "" : "s"} to Firebase');
      }
    } catch (e) {
      await Helperfunctions.showLoading(showLoading: false);
      if (mounted) {
        ShowMessage.error(context, 'Failed to upload error logs: $e');
      }
    }
  }

  Widget _buildDrawerItem(IconData icon, String title, Widget? nextPage, {bool isLogout = false, int badgeCount = 0, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : null, size: 22),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isLogout ? Colors.red : null),
      ),
      trailing: badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: () async {
        Navigator.pop(context);
        if (onTap != null) {
          onTap();
        } else if (isLogout) {
          _onLogout();
        } else if (nextPage != null) {
          await Helperfunctions.navigateThenWait(context, nextPage);
          if (mounted) await _syncDashboard();
        }
      },
    );
  }

  Widget _buildHomeDashboard() {
    return Scaffold(
      drawer: _buildDrawer(),
      appBar: CustomAppbar(
        title: 'Salesman Dashboard',
        subtitle: 'Field Sales Operations',
        showBackButton: false,
        centerTitle: false,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Open Menu',
          ),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            onPressed: _isSyncing ? null : _syncDashboard,
            tooltip: 'Sync Dashboard',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: _onLogout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BookOrderPage()));
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
        label: const Text('Book Order', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _syncDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Salesman Welcome Banner
                    _buildWelcomeBanner(),

                    const SizedBox(height: 20),

                    // 2. Primary Operations Quick Access
                    _buildSectionHeader('Operations Quick Access', 'Book orders, picklists, deliveries, and daily execution'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Book Order',
                            icon: Icons.add_shopping_cart_rounded,
                            iconColor: const Color(0xFF059669),
                            nextPage: const BookOrderPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StreamBuilder<int>(
                            stream: _pendingPicklistsCountStream,
                            initialData: _dashboardDTO.pendingPicklistCount,
                            builder: (context, snapshot) {
                              return _buildQuickAccessCard(
                                label: 'Picklists',
                                icon: Icons.fact_check_outlined,
                                count: snapshot.data ?? 0,
                                iconColor: const Color(0xFF7C3AED),
                                onTap: () => setState(() => _currentTabIndex = 2),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StreamBuilder<int>(
                            stream: _pendingDeliveriesCountStream,
                            initialData: _dashboardDTO.pendingDeliveryCount,
                            builder: (context, snapshot) {
                              return _buildQuickAccessCard(
                                label: 'Deliveries',
                                icon: Icons.local_shipping_outlined,
                                count: snapshot.data ?? _dashboardDTO.pendingDeliveryCount,
                                iconColor: const Color(0xFF2563EB),
                                onTap: () => setState(() => _currentTabIndex = 3),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Scanning',
                            icon: Icons.qr_code_scanner_outlined,
                            count: _dashboardDTO.totalNotScannedCount + _dashboardDTO.totalUnassignedCount,
                            iconColor: const Color(0xFFD97706),
                            onTap: () => setState(() => _currentTabIndex = 4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'PJP',
                            icon: Icons.map_outlined,
                            count: _dashboardDTO.pendingPjpCount,
                            iconColor: const Color(0xFF0F766E),
                            onTap: () => setState(() => _currentTabIndex = 1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StreamBuilder<int>(
                            stream: _tasksCountStream,
                            builder: (context, snapshot) {
                              return _buildQuickAccessCard(
                                label: 'Tasks',
                                icon: Icons.task_alt_outlined,
                                count: snapshot.data ?? 0,
                                iconColor: const Color(0xFF059669),
                                nextPage: const TaskListPage(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: StreamBuilder<int>(
                            stream: _merchBlitzCountStream,
                            builder: (context, snapshot) {
                              return _buildQuickAccessCard(
                                label: 'Merch Blitz',
                                icon: Icons.campaign_outlined,
                                count: snapshot.data ?? 0,
                                iconColor: const Color(0xFF0284C7),
                                nextPage: const MerchBlitzListPage(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'Placement',
                            icon: Icons.grid_view_outlined,
                            iconColor: const Color(0xFF0891B2),
                            nextPage: const PlacementlistPage(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildQuickAccessCard(
                            label: 'End of Day',
                            icon: Icons.today_outlined,
                            iconColor: const Color(0xFFD97706),
                            nextPage: const EndofdayPage(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBadge({
    required Stream<int> stream,
    required int initialCount,
    required IconData icon,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      initialData: initialCount,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count <= 0) return Icon(icon);
        return Badge.count(
          count: count,
          child: Icon(icon),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildHomeDashboard(),
          const PjpListPage(),
          const PicklistListPage(),
          const DeliveryListPage(),
          const ScanninglistPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        height: 65,
        elevation: 3,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Route',
          ),
          NavigationDestination(
            icon: _buildBadge(
              stream: _pendingPicklistsCountStream,
              initialCount: _dashboardDTO.pendingPicklistCount,
              icon: Icons.fact_check_outlined,
            ),
            selectedIcon: _buildBadge(
              stream: _pendingPicklistsCountStream,
              initialCount: _dashboardDTO.pendingPicklistCount,
              icon: Icons.fact_check_rounded,
            ),
            label: 'PickLists',
          ),
          NavigationDestination(
            icon: _buildBadge(
              stream: _pendingDeliveriesCountStream,
              initialCount: _dashboardDTO.pendingDeliveryCount,
              icon: Icons.local_shipping_outlined,
            ),
            selectedIcon: _buildBadge(
              stream: _pendingDeliveriesCountStream,
              initialCount: _dashboardDTO.pendingDeliveryCount,
              icon: Icons.local_shipping_rounded,
            ),
            label: 'Deliveries',
          ),
          const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scan',
          ),
        ],
      ),
    );
  }
}
