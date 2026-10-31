import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:selecta_ops/services/notification_badge_service.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';
import 'package:selecta_ops/views/pages/dashboard/deliverylist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_list_page.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/pages/others/notifications_page.dart';
import 'package:selecta_ops/views/pages/sidebar/inventory_page.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorderlist_page.dart';
import 'package:selecta_ops/views/pages/sidebar/superadmin_page.dart';
import 'package:selecta_ops/views/widgets/ai_chat_modal.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/controllers/attendance_controller.dart';
import 'package:selecta_ops/views/widgets/attendance/dealer_attendance_sheet.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_drawer.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_kpi_section.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_quick_access.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_sidebar.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_welcome_banner.dart';
import 'package:selecta_ops/views/widgets/dashboard/unverified_banner.dart';
import 'package:selecta_ops/views/widgets/exit_guard.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _homeScaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ScaffoldState> _phoneScaffoldKey = GlobalKey<ScaffoldState>();
  // Controller handling dashboard sync, data caching, live count streams, and role switching
  final DashboardController _controller = DashboardController();
  final AttendanceController _attendanceController = AttendanceController();

  late final Stream<int> _tasksCountStream;
  late final Stream<int> _merchBlitzCountStream;
  late final Stream<int> _purchaseOrdersAwaitingCountStream;
  late final Stream<int> _pendingPicklistsCountStream;
  late final Stream<int> _pendingDeliveriesCountStream;
  late final Stream<int> _activeReturnsCountStream;
  late final Stream<int> _unverifiedBreakdownsCountStream;
  late final Stream<UnverifiedSummary> _unverifiedSummaryStream;
  DashboardDTO dashboardDTO = DashboardDTO.empty();
  Users? _currentUser;
  Configuration? _configuration;
  StreamSubscription<Configuration?>? _configSubscription;
  bool isDealer = false;
  bool isSyncing = false;
  String lastSyncDateTime = '';
  DateTime? _lastSyncTime;
  int _currentTabIndex = 0;
  bool _isSidebarOpen = true;
  final GlobalKey<NavigatorState> _rightPaneNavKey = GlobalKey<NavigatorState>();
  final ValueNotifier<int> _dashboardVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isSecondaryPageOpenNotifier = ValueNotifier<bool>(false);
  late final _RightPaneNavigatorObserver _rightPaneObserver = _RightPaneNavigatorObserver(_isSecondaryPageOpenNotifier);
  StreamSubscription<RemoteMessage>? _fcmSub;

  void _toggleSidebar() {
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _dashboardVersionNotifier.value++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    dashboardNeedsRefreshNotifier.addListener(_refreshDashboardIfNeeded);
    _tasksCountStream = _controller.getTasksPendingAndOverdueCountStream();
    _merchBlitzCountStream = _controller.getMerchBlitzCountStream(forDealer: true);
    _purchaseOrdersAwaitingCountStream = _controller.getPurchaseOrdersAwaitingCountStream();
    _pendingPicklistsCountStream = _controller.getPendingPicklistsCountStream();
    _pendingDeliveriesCountStream = _controller.getPendingDeliveriesCountStream();
    _activeReturnsCountStream = _controller.getActiveReturnsCountStream();
    _unverifiedBreakdownsCountStream = _controller.getUnverifiedBreakdownsCountStream();
    _unverifiedSummaryStream = _controller.getUnverifiedSummaryStream();
    _configSubscription = ConfigurationService().getConfigurationStream().listen((config) {
      if (mounted && config != null) {
        setState(() {
          _configuration = config;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
    _fcmSub = PushNotificationService().onForegroundMessage.listen((msg) {
      final n = msg.notification;
      if (!mounted || n == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    if (n.body != null && n.body!.isNotEmpty)
                      Text(n.body!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => _navigateToPage(const NotificationsPage(roles: NotificationAudience.dealer)),
          ),
        ),
      );
      NotificationBadgeService().onPushReceived();
    });
    NotificationBadgeService().refresh(NotificationAudience.dealer, force: true);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    dashboardNeedsRefreshNotifier.removeListener(_refreshDashboardIfNeeded);
    _configSubscription?.cancel();
    _dashboardVersionNotifier.dispose();
    _isSecondaryPageOpenNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoSyncIfStaleOrRequested();
      NotificationBadgeService().refresh(NotificationAudience.dealer);
    }
  }

  /// Automatically triggers a silent sync when resuming if the cache is stale (>30 mins) or requested.
  Future<void> _autoSyncIfStaleOrRequested() async {
    if (isSyncing || !mounted) return;
    final isStale = await DashboardController.isCacheStale();
    if (isStale || dashboardNeedsRefreshNotifier.value) {
      dashboardNeedsRefreshNotifier.value = false;
      await syncDashboard(force: false);
    }
  }

  // Load user info and cached metrics via DashboardController
  void prefetchData() async {
    final user = await _controller.getCurrentUser();
    final isDealerRole = user?.role == BusinessRole.dealer;
    final config = await ConfigurationService().getConfiguration();
    await _syncDashboardFromSharedPreferences();
    if (mounted) {
      setState(() {
        _currentUser = user;
        isDealer = isDealerRole;
        _configuration = config;
      });
      AppUpdateService.checkAndPromptUpdate(context, silent: true);
    }
  }

  // Compute fresh dashboard totals and refresh view
  Future<void> syncDashboard({bool force = true}) async {
    if (isSyncing) return;
    if (!mounted) return;

    setState(() {
      isSyncing = true;
    });

    try {
      // Process pending offline orders and updates first
      await OfflineSyncService.instance.processQueue();

      final newDto = await DashboardController.getLatestDashboardData(force: force);
      final newSync = await DashboardController.getLastSync();
      final newSyncTime = await DashboardController.getLastSyncDateTime();
      if (mounted) {
        setState(() {
          dashboardDTO = newDto;
          lastSyncDateTime = newSync;
          _lastSyncTime = newSyncTime;
        });
      }
      // save in shared preferences
      await _controller.saveDashboardData(newDto, newSync);
    } catch (e, s) {
      debugPrint('Error syncing dashboard: $e');
      ErrorLogService.logError(page: 'DashboardPage', action: 'Sync Dashboard Data', error: e, stackTrace: s);
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
    }
  }

  Future<void> _refreshDashboardIfNeeded() async {
    if (!dashboardNeedsRefreshNotifier.value) {
      return;
    }

    dashboardNeedsRefreshNotifier.value = false;
    await syncDashboard(force: false);
  }

  // Synchronize dashboard state from local cache via Stale-While-Revalidate (SWR)
  Future<void> _syncDashboardFromSharedPreferences() async {
    // 1. Immediately render cached data for instant 0ms startup
    final cachedDashboard = await _controller.getCachedDashboardData();
    final cachedLastSync = await DashboardController.getLastSync();
    final cachedLastSyncTime = await DashboardController.getLastSyncDateTime();
    if (mounted) {
      setState(() {
        if (cachedDashboard != null) {
          dashboardDTO = cachedDashboard;
        }
        lastSyncDateTime = cachedLastSync;
        _lastSyncTime = cachedLastSyncTime;
      });
    }

    // 2. Stale-While-Revalidate: Silently sync in background if cache is stale (>30 mins / different day)
    final isStale = await DashboardController.isCacheStale();
    if (cachedDashboard == null || isStale) {
      await syncDashboard(force: false);
    }
  }

  // Logout via DashboardController
  void onLogout() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to log out of your account?',
      isDestructive: true,
      icon: Icons.logout_rounded,
      confirmText: 'Log Out',
    );

    if (confirmed) {
      if (!mounted) return;
      try {
        await ShowMessage.runWithLoading(
          context,
          message: 'Signing out...',
          task: () async {
            await _controller.signOut();
          },
        );
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'There was a problem upon signing out: $e');
        }
      }
    }
  }

  Future<void> _navigateToPage(Widget page) async {
    final isDesktop = ScreenSize.isDesktop(context);
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final isWide = isDesktop || isTabletLandscape;

    if (page is PurchaseorderlistPage) {
      if (isWide) {
        _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
      }
      setState(() => _currentTabIndex = 1);
      return;
    }
    if (page is InventoryPage) {
      if (isWide) {
        _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
      }
      setState(() => _currentTabIndex = 2);
      return;
    }
    if (page is PicklistListPage) {
      if (isWide) {
        _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
      }
      setState(() => _currentTabIndex = 3);
      return;
    }
    if (page is DeliveryListPage) {
      if (isWide) {
        _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
      }
      setState(() => _currentTabIndex = 4);
      return;
    }

    if (isWide) {
      _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
      await _rightPaneNavKey.currentState?.push(
        MaterialPageRoute(builder: (_) => page),
      );
      if (mounted) await _refreshDashboardIfNeeded();
      return;
    }

    await Helperfunctions.navigateThenWait(context, page);
    if (mounted) await _refreshDashboardIfNeeded();
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

    final enteredPassword = passwordController.text.trim();
    if (enteredPassword.isEmpty) {
      if (mounted) ShowMessage.error(context, 'Password cannot be empty.');
      return;
    }

    // Fetch the stored hash from Firestore config
    final config = await ConfigurationService().getConfiguration();

    if (config.superAdminPasswordHash.isEmpty) {
      // No hash set yet — allow entry with a warning so admin can set one immediately
      if (mounted) {
        ShowMessage.alert(
          context,
          title: 'No Admin Password Set',
          message: 'No super-admin password has been configured yet. Please set one from the Super Admin page immediately.',
          icon: Icons.warning_amber_rounded,
        );
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SuperAdminPage()));
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          if (dashboardNeedsRefreshNotifier.value) {
            dashboardNeedsRefreshNotifier.value = false;
            await syncDashboard(force: false);
          }
        }
      }
      return;
    }

    if (!config.verifyAdminPassword(enteredPassword)) {
      if (mounted) {
        ShowMessage.error(context, 'Incorrect admin password.');
      }
      return;
    }

    if (mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SuperAdminPage()));
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        if (dashboardNeedsRefreshNotifier.value) {
          dashboardNeedsRefreshNotifier.value = false;
          await syncDashboard(force: false);
        }
      }
    }
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── Shared sidebar props helper ─────────────────────────────────────────
  DashboardSidebar _buildSidebar({
    bool includeTabs = false,
    int? currentTabIndex,
    VoidCallback? onCollapse,
  }) => DashboardSidebar(
    currentUser: _currentUser,
    isDealer: isDealer,
    isSyncing: isSyncing,
    dashboardDTO: dashboardDTO,
    merchBlitzCountStream: _merchBlitzCountStream,
    tasksCountStream: _tasksCountStream,
    activeReturnsCountStream: _activeReturnsCountStream,
    unverifiedBreakdownCountStream: _unverifiedBreakdownsCountStream,
    currentTabIndex: includeTabs ? (currentTabIndex ?? _currentTabIndex) : null,
    onTabSelected: includeTabs
        ? (index) {
            _rightPaneNavKey.currentState?.popUntil((route) => route.isFirst);
            setState(() => _currentTabIndex = index);
          }
        : null,
    purchaseOrdersAwaitingCountStream: includeTabs ? _purchaseOrdersAwaitingCountStream : null,
    pendingPicklistsCountStream: includeTabs ? _pendingPicklistsCountStream : null,
    pendingDeliveriesCountStream: includeTabs ? _pendingDeliveriesCountStream : null,
    onSync: () => syncDashboard(force: true),
    onLogout: onLogout,
    onNavigate: _navigateToPage,
    onCollapse: onCollapse,
  );

  /// The scrollable dashboard body — shared across all screen sizes.
  Widget _buildDashboardBody() {
    final padding = ScreenSize.pagePadding(context);
    return RefreshIndicator(
      onRefresh: () => syncDashboard(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ScreenSize.contentMaxWidth(context)),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [
                  // 1. User Welcome & Last Sync Banner
                  DashboardWelcomeBanner(
                    currentUser: _currentUser,
                    isDealer: isDealer,
                    lastSyncDateTime: lastSyncDateTime,
                    lastSyncTime: _lastSyncTime,
                    isSyncing: isSyncing,
                    onSyncTap: () => syncDashboard(force: true),
                    onSecretTap: _showSecretRoleSwitchDialog,
                  ),

                  // 1a. Needs Verification Banner (Dealer backlog alert & in-app reminder)
                  if (isDealer)
                    UnverifiedBanner(
                      summary: UnverifiedSummary(
                        count: dashboardDTO.unverifiedBreakdownCount,
                        oldest: dashboardDTO.oldestUnverifiedDate,
                        dates: dashboardDTO.oldestUnverifiedDate != null ? {dashboardDTO.oldestUnverifiedDate!} : {},
                      ),
                      summaryStream: _unverifiedSummaryStream,
                      onNavigate: _navigateToPage,
                    ),

                  // 1b. Dealer Salesman Attendance Banner
                  if (isDealer && _currentUser != null)
                    _buildDealerAttendanceBanner(),

                  // 2. Quick Access Section
                  _buildSectionHeader('Quick Access', 'Orders, credits, van operations, and scouting'),
                  DashboardQuickAccessGrid(
                    dashboardDTO: dashboardDTO,
                    pendingPicklistsCountStream: _pendingPicklistsCountStream,
                    purchaseOrdersAwaitingCountStream: _purchaseOrdersAwaitingCountStream,
                    activeReturnsCountStream: _activeReturnsCountStream,
                    unverifiedBreakdownsCountStream: _unverifiedBreakdownsCountStream,
                    onNavigate: _navigateToPage,
                  ),

                  // 3. Operational Metrics / KPI Section
                  _buildSectionHeader('Performance KPIs', 'Sales, throughput, and store coverage'),
                  DashboardKpiSection(dashboardDTO: dashboardDTO, configuration: _configuration, isSyncing: isSyncing, onNavigate: _navigateToPage),
                ],
              ),
            ),
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

  Widget _buildDealerAttendanceBanner() {
    if (_currentUser == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<int>(
      stream: _attendanceController.streamPendingCount(
        _currentUser!.dealerName,
        DateTime.now(),
      ),
      builder: (context, snapshot) {
        final pendingCount = snapshot.data ?? 0;
        final hasPending = pendingCount > 0;

        return Card(
          elevation: 0,
          color: hasPending
              ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
              : colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: hasPending
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => DealerAttendanceSheet.show(context, dealer: _currentUser!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hasPending
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                          : colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hasPending ? Icons.notification_important_rounded : Icons.badge_outlined,
                      color: hasPending ? const Color(0xFFD97706) : colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Salesman Attendance',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (hasPending) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$pendingCount Pending',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPending
                              ? '$pendingCount request(s) awaiting your confirmation.'
                              : 'All salesmen attendances up to date. Tap to view crew timecards.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bottom NavigationBar destinations — 5 tabs with live count badges
  List<NavigationDestination> _navDestinations() => [
    const NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: _buildBadge(
        stream: _purchaseOrdersAwaitingCountStream,
        initialCount: 0,
        icon: Icons.inventory_2_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _purchaseOrdersAwaitingCountStream,
        initialCount: 0,
        icon: Icons.inventory_2_rounded,
      ),
      label: 'Restock',
    ),
    const NavigationDestination(
      icon: Icon(Icons.warehouse_outlined),
      selectedIcon: Icon(Icons.warehouse_rounded),
      label: 'Inventory',
    ),
    NavigationDestination(
      icon: _buildBadge(
        stream: _pendingPicklistsCountStream,
        initialCount: dashboardDTO.pendingPicklistCount,
        icon: Icons.fact_check_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _pendingPicklistsCountStream,
        initialCount: dashboardDTO.pendingPicklistCount,
        icon: Icons.fact_check_rounded,
      ),
      label: 'PickLists',
    ),
    NavigationDestination(
      icon: _buildBadge(
        stream: _pendingDeliveriesCountStream,
        initialCount: dashboardDTO.pendingDeliveryCount,
        icon: Icons.local_shipping_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _pendingDeliveriesCountStream,
        initialCount: dashboardDTO.pendingDeliveryCount,
        icon: Icons.local_shipping_rounded,
      ),
      label: 'Deliveries',
    ),
  ];

  /// NavigationRail destinations for tablet
  List<NavigationRailDestination> _navRailDestinations() => [
    const NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: _buildBadge(
        stream: _purchaseOrdersAwaitingCountStream,
        initialCount: 0,
        icon: Icons.inventory_2_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _purchaseOrdersAwaitingCountStream,
        initialCount: 0,
        icon: Icons.inventory_2_rounded,
      ),
      label: const Text('Restock'),
    ),
    const NavigationRailDestination(
      icon: Icon(Icons.warehouse_outlined),
      selectedIcon: Icon(Icons.warehouse_rounded),
      label: Text('Inventory'),
    ),
    NavigationRailDestination(
      icon: _buildBadge(
        stream: _pendingPicklistsCountStream,
        initialCount: dashboardDTO.pendingPicklistCount,
        icon: Icons.fact_check_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _pendingPicklistsCountStream,
        initialCount: dashboardDTO.pendingPicklistCount,
        icon: Icons.fact_check_rounded,
      ),
      label: const Text('PickLists'),
    ),
    NavigationRailDestination(
      icon: _buildBadge(
        stream: _pendingDeliveriesCountStream,
        initialCount: dashboardDTO.pendingDeliveryCount,
        icon: Icons.local_shipping_outlined,
      ),
      selectedIcon: _buildBadge(
        stream: _pendingDeliveriesCountStream,
        initialCount: dashboardDTO.pendingDeliveryCount,
        icon: Icons.local_shipping_rounded,
      ),
      label: const Text('Deliveries'),
    ),
  ];

  void _openDrawer() {
    if (_phoneScaffoldKey.currentState != null) {
      _phoneScaffoldKey.currentState!.openDrawer();
    } else {
      _homeScaffoldKey.currentState?.openDrawer();
    }
  }

  Widget _buildDrawer() => DashboardDrawer(
    currentUser: _currentUser,
    isDealer: isDealer,
    isSyncing: isSyncing,
    dashboardDTO: dashboardDTO,
    merchBlitzCountStream: _merchBlitzCountStream,
    tasksCountStream: _tasksCountStream,
    activeReturnsCountStream: _activeReturnsCountStream,
    unverifiedBreakdownCountStream: _unverifiedBreakdownsCountStream,
    onSync: () => syncDashboard(force: true),
    onLogout: onLogout,
    onNavigate: _navigateToPage,
  );

  bool _handleBackPress() {
    if (_phoneScaffoldKey.currentState?.isDrawerOpen == true) {
      _phoneScaffoldKey.currentState?.closeDrawer();
      return true;
    }
    if (_homeScaffoldKey.currentState?.isDrawerOpen == true) {
      _homeScaffoldKey.currentState?.closeDrawer();
      return true;
    }
    if (_rightPaneNavKey.currentState?.canPop() == true) {
      _rightPaneNavKey.currentState?.pop();
      return true;
    }
    if (_currentTabIndex != 0) {
      setState(() => _currentTabIndex = 0);
      return true;
    }
    return false;
  }

  Widget _buildHomeDashboard(List<Widget> appBarActions, ColorScheme colorScheme, {required bool isWideLandscape}) {
    return Scaffold(
      key: _homeScaffoldKey,
      appBar: CustomAppbar(
        title: 'Dashboard',
        subtitle: 'Selecta Operations',
        showBackButton: false,
        leading: isWideLandscape
            ? null
            : IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onPressed: _openDrawer,
                tooltip: 'Open Menu',
              ),
        actions: appBarActions,
      ),
      drawer: isWideLandscape ? null : _buildDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => AiChatModal.show(context, dashboardDTO: dashboardDTO, userRole: isDealer ? 'Dealer' : 'Salesman'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text('Ask Sedy', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _buildDashboardBody(),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) => [
    IconButton(
      icon: ValueListenableBuilder<int>(
        valueListenable: NotificationBadgeService().unreadCount,
        builder: (_, count, child) => Badge(
          isLabelVisible: count > 0,
          label: Text(count > 9 ? '9+' : '$count'),
          child: child,
        ),
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
      onPressed: () => _navigateToPage(const NotificationsPage(roles: NotificationAudience.dealer)),
      tooltip: 'Notifications',
    ),
    IconButton(
      icon: isSyncing
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.sync_rounded, color: Colors.white),
      onPressed: isSyncing ? null : () => syncDashboard(force: true),
      tooltip: 'Sync Dashboard',
    ),
  ];

  List<Widget> _buildTabPages(BuildContext context, {required bool isWideLandscape}) {
    final VoidCallback? onOpenDrawer = isWideLandscape ? null : _openDrawer;
    return [
      _buildHomeDashboard(_buildAppBarActions(context), Theme.of(context).colorScheme, isWideLandscape: isWideLandscape),
      PurchaseorderlistPage(onOpenDrawer: onOpenDrawer),
      InventoryPage(onOpenDrawer: onOpenDrawer),
      PicklistListPage(onOpenDrawer: onOpenDrawer),
      DeliveryListPage(onOpenDrawer: onOpenDrawer),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ScreenSize.isDesktop(context);
    final isTablet = ScreenSize.isTablet(context);
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final isWide = isDesktop || isTabletLandscape;
    final colorScheme = Theme.of(context).colorScheme;

    final Widget content;

    // ── DESKTOP / TABLET LANDSCAPE: Unified single sidebar + tab content ──
    if (isWide) {
      content = Scaffold(
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  width: _isSidebarOpen ? DashboardSidebar.kWidth : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      minWidth: DashboardSidebar.kWidth,
                      maxWidth: DashboardSidebar.kWidth,
                      alignment: Alignment.topLeft,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isSecondaryPageOpenNotifier,
                        builder: (ctx, isSecondaryOpen, _) {
                          return _buildSidebar(
                            includeTabs: true,
                            currentTabIndex: isSecondaryOpen ? -1 : _currentTabIndex,
                            onCollapse: _toggleSidebar,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (_isSidebarOpen) const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: Navigator(
                    key: _rightPaneNavKey,
                    observers: [_rightPaneObserver],
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute(
                        builder: (navContext) => ValueListenableBuilder<int>(
                          valueListenable: _dashboardVersionNotifier,
                          builder: (context, version, child) {
                            return IndexedStack(
                              index: _currentTabIndex,
                              children: _buildTabPages(context, isWideLandscape: true),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            if (!_isSidebarOpen)
              ValueListenableBuilder<bool>(
                valueListenable: _isSecondaryPageOpenNotifier,
                builder: (ctx, isSecondaryOpen, _) {
                  return Positioned(
                    top: MediaQuery.paddingOf(context).top + 16,
                    left: isSecondaryOpen ? 62 : 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.brightness == Brightness.dark
                            ? const Color(0xFF28303F)
                            : Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.menu_rounded, size: 20, color: Colors.white),
                        onPressed: _toggleSidebar,
                        tooltip: 'Show Sidebar',
                        splashRadius: 20,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    } else if (isTablet) {
      // ── TABLET PORTRAIT layout: NavigationRail + tab content (drawer for operations) ──
      content = Scaffold(
        key: _phoneScaffoldKey,
        drawer: _buildDrawer(),
        body: Row(
          children: [
            SafeArea(
              bottom: false,
              right: false,
              child: NavigationRail(
                selectedIndex: _currentTabIndex,
                onDestinationSelected: (index) {
                  setState(() => _currentTabIndex = index);
                },
                labelType: NavigationRailLabelType.selected,
                minWidth: 56,
                destinations: _navRailDestinations(),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: _buildTabPages(context, isWideLandscape: false),
              ),
            ),
          ],
        ),
      );
    } else {
      // ── PHONE layout: persistent bottom nav + IndexedStack ───────────────
      content = Scaffold(
        key: _phoneScaffoldKey,
        drawer: _buildDrawer(),
        body: IndexedStack(
          index: _currentTabIndex,
          children: _buildTabPages(context, isWideLandscape: false),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          height: 65,
          elevation: 3,
          onDestinationSelected: (index) {
            setState(() => _currentTabIndex = index);
          },
          destinations: _navDestinations(),
        ),
      );
    }

    return ExitGuard(
      onBackIntercept: _handleBackPress,
      child: content,
    );
  }
}

/// Navigator observer that notifies whether the right pane Navigator has any pushed routes.
class _RightPaneNavigatorObserver extends NavigatorObserver {
  final ValueNotifier<bool> secondaryPageNotifier;
  _RightPaneNavigatorObserver(this.secondaryPageNotifier);

  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      secondaryPageNotifier.value = navigator?.canPop() ?? false;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _update();
  }
}
