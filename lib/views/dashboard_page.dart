import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
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
import 'package:selecta_ops/views/widgets/dashboard/dashboard_drawer.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_kpi_section.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_quick_access.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_sidebar.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_welcome_banner.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Controller handling dashboard sync, data caching, live count streams, and role switching
  final DashboardController _controller = DashboardController();

  late final Stream<int> _tasksCountStream;
  late final Stream<int> _merchBlitzCountStream;
  late final Stream<int> _purchaseOrdersAwaitingCountStream;
  late final Stream<int> _pendingPicklistsCountStream;
  late final Stream<int> _pendingDeliveriesCountStream;
  DashboardDTO dashboardDTO = DashboardDTO.empty();
  Users? _currentUser;
  Configuration? _configuration;
  StreamSubscription<Configuration?>? _configSubscription;
  bool isDealer = false;
  bool isSyncing = false;
  String lastSyncDateTime = '';
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tasksCountStream = _controller.getTasksPendingAndOverdueCountStream();
    _merchBlitzCountStream = _controller.getMerchBlitzCountStream(forDealer: true);
    _purchaseOrdersAwaitingCountStream = _controller.getPurchaseOrdersAwaitingCountStream();
    _pendingPicklistsCountStream = _controller.getPendingPicklistsCountStream();
    _pendingDeliveriesCountStream = _controller.getPendingDeliveriesCountStream();
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
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    super.dispose();
  }

  Future<void> showLoading(bool showLoading) async {
    if (showLoading) {
      if (mounted) await Helperfunctions.showLoading(context: context, showLoading: true);
    } else {
      await Helperfunctions.showLoading(context: context, showLoading: false);
    }
  }

  // Load user info and cached metrics via DashboardController
  void prefetchData() async {
    final user = await _controller.getCurrentUser();
    final isDealerRole = user?.role == BusinessRole.dealer;
    final lastSync = await DashboardController.getLastSync();
    final config = await ConfigurationService().getConfiguration();
    await _syncDashboardFromSharedPreferences();
    if (mounted) {
      setState(() {
        _currentUser = user;
        isDealer = isDealerRole;
        lastSyncDateTime = lastSync;
        _configuration = config;
      });
      AppUpdateService.checkAndPromptUpdate(context, silent: true);
    }
  }

  // Compute fresh dashboard totals and refresh view
  Future<void> syncDashboard() async {
    if (!mounted) return;

    showLoading(true);
    setState(() {
      isSyncing = true;
      dashboardDTO = DashboardDTO.empty();
    });

    try {
      // Process pending offline orders and updates first
      await OfflineSyncService.instance.processQueue();

      dashboardDTO = await DashboardController.getLatestDashboardData();
      lastSyncDateTime = await DashboardController.getLastSync();
      // save in shared preferences
      await _controller.saveDashboardData(dashboardDTO, lastSyncDateTime);
    } catch (e, s) {
      debugPrint('Error syncing dashboard: $e');
      ErrorLogService.logError(page: 'DashboardPage', action: 'Sync Dashboard Data', error: e, stackTrace: s);
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
      await showLoading(false);
    }
  }

  Future<void> _refreshDashboardIfNeeded() async {
    if (!dashboardNeedsRefreshNotifier.value) {
      await _syncDashboardFromSharedPreferences();
      return;
    }

    dashboardNeedsRefreshNotifier.value = false;
    await syncDashboard();
  }

  // Synchronize dashboard state from local cache via controller
  Future<void> _syncDashboardFromSharedPreferences() async {
    final isToday = await DashboardController.isLastSyncToday();
    if (!isToday) {
      await syncDashboard();
      return;
    }

    final cachedDashboard = await _controller.getCachedDashboardData();
    if (cachedDashboard == null || !mounted) {
      await syncDashboard();
      return;
    }

    final cachedLastSync = await DashboardController.getLastSync();
    if (!mounted) return;

    setState(() {
      dashboardDTO = cachedDashboard;
      lastSyncDateTime = cachedLastSync;
    });
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
      try {
        await _controller.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'There was a problem upon signing out');
        }
      }
    }
  }

  Future<void> _navigateToPage(Widget page) async {
    if (page is PurchaseorderlistPage) {
      setState(() => _currentTabIndex = 1);
      return;
    }
    if (page is InventoryPage) {
      setState(() => _currentTabIndex = 2);
      return;
    }
    if (page is PicklistListPage) {
      setState(() => _currentTabIndex = 3);
      return;
    }
    if (page is DeliveryListPage) {
      setState(() => _currentTabIndex = 4);
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
          await syncDashboard();
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
        await syncDashboard();
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
  DashboardSidebar _buildSidebar() => DashboardSidebar(
    currentUser: _currentUser,
    isDealer: isDealer,
    isSyncing: isSyncing,
    dashboardDTO: dashboardDTO,
    merchBlitzCountStream: _merchBlitzCountStream,
    tasksCountStream: _tasksCountStream,
    onSync: syncDashboard,
    onLogout: onLogout,
    onNavigate: _navigateToPage,
  );

  /// The scrollable dashboard body — shared across all screen sizes.
  Widget _buildDashboardBody() {
    final padding = ScreenSize.pagePadding(context);
    return RefreshIndicator(
      onRefresh: syncDashboard,
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
                    onSecretTap: _showSecretRoleSwitchDialog,
                  ),

                  // 2. Quick Access Section
                  _buildSectionHeader('Quick Access', 'Pending deliveries, purchase orders, and credits'),
                  DashboardQuickAccessGrid(
                    dashboardDTO: dashboardDTO,
                    pendingPicklistsCountStream: _pendingPicklistsCountStream,
                    purchaseOrdersAwaitingCountStream: _purchaseOrdersAwaitingCountStream,
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

  Widget _buildHomeDashboard(List<Widget> appBarActions, ColorScheme colorScheme) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Dashboard',
        subtitle: 'Selecta Operations',
        showBackButton: false,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Open Menu',
          ),
        ),
        actions: appBarActions,
      ),
      drawer: DashboardDrawer(
        currentUser: _currentUser,
        isDealer: isDealer,
        isSyncing: isSyncing,
        dashboardDTO: dashboardDTO,
        merchBlitzCountStream: _merchBlitzCountStream,
        tasksCountStream: _tasksCountStream,
        onSync: syncDashboard,
        onLogout: onLogout,
        onNavigate: _navigateToPage,
      ),
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = ScreenSize.isDesktop(context);
    final isTablet = ScreenSize.isTablet(context);
    final colorScheme = Theme.of(context).colorScheme;

    // ── AppBar actions (shared) ────────────────────────────────────────────
    final appBarActions = [
      IconButton(
        icon: const Icon(Icons.notifications_outlined, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
        tooltip: 'Notifications',
      ),
      IconButton(
        icon: isSyncing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync_rounded, color: Colors.white),
        onPressed: isSyncing ? null : syncDashboard,
        tooltip: 'Sync Dashboard',
      ),
    ];

    final tabPages = [
      _buildHomeDashboard(appBarActions, colorScheme),
      const PurchaseorderlistPage(),
      const InventoryPage(),
      const PicklistListPage(),
      const DeliveryListPage(),
    ];

    // ── DESKTOP layout: permanent sidebar + tab content ────────────────────────
    if (isDesktop) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSidebar(),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: tabPages,
              ),
            ),
          ],
        ),
      );
    }

    // ── TABLET layout: NavigationRail + tab content ─────────────────────
    if (isTablet) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentTabIndex,
              onDestinationSelected: (index) {
                setState(() => _currentTabIndex = index);
              },
              labelType: NavigationRailLabelType.selected,
              minWidth: 56,
              destinations: _navRailDestinations(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: tabPages,
              ),
            ),
          ],
        ),
      );
    }

    // ── PHONE layout: persistent bottom nav + IndexedStack ───────────────
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: tabPages,
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
}
