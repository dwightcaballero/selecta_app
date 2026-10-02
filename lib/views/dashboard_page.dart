import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/app_update_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/deliverylist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/pjplist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/scanninglist_page.dart';
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
  DashboardDTO dashboardDTO = DashboardDTO.empty();
  Users? _currentUser;
  Configuration? _configuration;
  StreamSubscription<Configuration?>? _configSubscription;
  bool isDealer = false;
  bool isSyncing = false;
  String lastSyncDateTime = '';

  @override
  void initState() {
    super.initState();
    _tasksCountStream = _controller.getTasksPendingAndOverdueCountStream();
    _merchBlitzCountStream = _controller.getMerchBlitzCountStream(forDealer: true);
    _purchaseOrdersAwaitingCountStream = _controller.getPurchaseOrdersAwaitingCountStream();
    _pendingPicklistsCountStream = _controller.getPendingPicklistsCountStream();
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

    await showLoading(true);
    try {
      final count = await ErrorLogService.uploadPendingLogs();
      if (!mounted) return;
      await showLoading(false);
      if (mounted) {
        ShowMessage.success(context, 'Successfully uploaded $count error log${count == 1 ? "" : "s"} to Firebase');
      }
    } catch (e) {
      await showLoading(false);
      if (mounted) {
        ShowMessage.error(context, 'Failed to upload error logs: $e');
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
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()));
            },
            tooltip: 'Notifications',
          ),
          IconButton(
            icon: isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            onPressed: isSyncing ? null : syncDashboard,
            tooltip: 'Sync Dashboard',
          ),
        ],
      ),
      drawer: DashboardDrawer(
        currentUser: _currentUser,
        isDealer: isDealer,
        isSyncing: isSyncing,
        dashboardDTO: dashboardDTO,
        merchBlitzCountStream: _merchBlitzCountStream,
        tasksCountStream: _tasksCountStream,
        onSync: syncDashboard,
        onUploadErrorLogs: _handleUploadErrorLogs,
        onLogout: onLogout,
        onCheckForUpdates: () => AppUpdateService.checkAndPromptUpdate(context, silent: false, forceRefresh: true),
        onNavigate: _navigateToPage,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          AiChatModal.show(context, dashboardDTO: dashboardDTO, userRole: isDealer ? 'Dealer' : 'Salesman');
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text('Ask Sedy', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: syncDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
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
              DashboardKpiSection(
                dashboardDTO: dashboardDTO,
                configuration: _configuration,
                isSyncing: isSyncing,
                onNavigate: _navigateToPage,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        height: 65,
        elevation: 3,
        onDestinationSelected: (index) {
          if (index == 0) return;
          if (isDealer) {
            switch (index) {
              case 1:
                _navigateToPage(const PurchaseorderlistPage());
                break;
              case 2:
                _navigateToPage(const InventoryPage());
                break;
              case 3:
                _navigateToPage(const PjpListPage());
                break;
              case 4:
                _navigateToPage(const ScanninglistPage());
                break;
            }
          } else {
            switch (index) {
              case 1:
                _navigateToPage(const PjpListPage());
                break;
              case 2:
                _navigateToPage(const DeliveryListPage());
                break;
              case 3:
                _navigateToPage(const BookOrderPage());
                break;
              case 4:
                _navigateToPage(const ScanninglistPage());
                break;
            }
          }
        },
        destinations: isDealer
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shopping_bag_outlined),
                  selectedIcon: Icon(Icons.shopping_bag_rounded),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Icon(Icons.warehouse_outlined),
                  selectedIcon: Icon(Icons.warehouse_rounded),
                  label: 'Inventory',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Route',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner_rounded),
                  label: 'Scan',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Route',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  selectedIcon: Icon(Icons.local_shipping_rounded),
                  label: 'Deliveries',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_shopping_cart_outlined),
                  selectedIcon: Icon(Icons.add_shopping_cart_rounded),
                  label: 'Book Order',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.qr_code_scanner_rounded),
                  label: 'Scan',
                ),
              ],
      ),
    );
  }
}
