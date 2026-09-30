import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/notifiers.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/views/pages/dashboard/buyinglist_page.dart';
import 'package:flutter_app/views/pages/dashboard/creditlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/deliverylist_page.dart';
import 'package:flutter_app/views/pages/dashboard/expansion_page.dart';
import 'package:flutter_app/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/pjplist_page.dart';
import 'package:flutter_app/views/pages/dashboard/placementlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/returnlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/sales_page.dart';
import 'package:flutter_app/views/pages/dashboard/scanninglist_page.dart';
import 'package:flutter_app/views/pages/dashboard/thruput_page.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/pages/sidebar/badorderlist_page.dart';
import 'package:flutter_app/views/pages/sidebar/configuration_page.dart';
import 'package:flutter_app/views/pages/sidebar/endofday_page.dart';
import 'package:flutter_app/views/pages/sidebar/expenselist_page.dart';
import 'package:flutter_app/views/pages/sidebar/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/sidebar/inventory_page.dart';
import 'package:flutter_app/views/pages/sidebar/other_products_page.dart';
import 'package:flutter_app/views/pages/sidebar/selecta_products_page.dart';
import 'package:flutter_app/views/pages/sidebar/purchaseorderlist_page.dart';
import 'package:flutter_app/views/pages/sidebar/tasklist_page.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlist_page.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlog_page.dart';
import 'package:flutter_app/services/error_log_service.dart';
import 'package:flutter_app/views/pages/sidebar/superadmin_page.dart';
import 'package:flutter_app/views/widgets/ai_chat_modal.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

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
  DashboardDTO dashboardDTO = DashboardDTO.empty();
  Users? _currentUser;
  bool isDealer = false;
  bool isSyncing = false;
  String lastSyncDateTime = '';

  @override
  void initState() {
    super.initState();
    _tasksCountStream = _controller.getTasksPendingAndOverdueCountStream();
    _merchBlitzCountStream = _controller.getMerchBlitzCountStream(forDealer: true);
    _purchaseOrdersAwaitingCountStream = _controller.getPurchaseOrdersAwaitingCountStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
  }

  Future<void> showLoading(bool showLoading) async {
    if (showLoading) {
      if (mounted) await Helperfunctions.showLoading(context: context, showLoading: true);
    } else {
      await Helperfunctions.showLoading(context: context, showLoading: false);
      if (mounted) setState(() {});
    }
  }

  // Load user info and cached metrics via DashboardController
  void prefetchData() async {
    _currentUser = await _controller.getCurrentUser();
    isDealer = _currentUser?.role == BusinessRole.dealer;
    lastSyncDateTime = await DashboardController.getLastSync();
    await _syncDashboardFromSharedPreferences();
    if (mounted) setState(() {});
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
      dashboardDTO = await DashboardController.getLatestDashboardData();
      lastSyncDateTime = await DashboardController.getLastSync();
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
        await syncDashboard();
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
    final displayName = _currentUser?.username ?? (isDealer ? 'Dealer' : 'Salesman');
    final hasSyncTime = lastSyncDateTime.isNotEmpty && lastSyncDateTime != 'Never';

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
              decoration: BoxDecoration(
                color: (isDealer ? colorScheme.primary : colorScheme.tertiary).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDealer ? Icons.store_rounded : Icons.badge_outlined,
                color: isDealer ? colorScheme.primary : colorScheme.tertiary,
                size: 24,
              ),
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
                        decoration: BoxDecoration(
                          color: (isDealer ? colorScheme.primary : colorScheme.tertiary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isDealer ? 'Dealer' : 'Salesman',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDealer ? colorScheme.primary : colorScheme.tertiary),
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
                          hasSyncTime ? 'Last synced: $lastSyncDateTime' : 'Not synced yet',
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
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildQuickAccessGrid() {
    return Row(
      spacing: 10,
      children: [
        _buildQuickAccessCard(
          label: 'Deliveries',
          icon: Icons.local_shipping_outlined,
          count: dashboardDTO.pendingDeliveryCount,
          color: Theme.of(context).colorScheme.primary,
          nextPage: const DeliveryListPage(),
        ),
        _buildQuickAccessCard(
          label: 'Purchase Orders',
          icon: Icons.assignment_outlined,
          stream: _purchaseOrdersAwaitingCountStream,
          color: Theme.of(context).colorScheme.primary,
          nextPage: const PurchaseorderlistPage(),
        ),
        _buildQuickAccessCard(
          label: 'Credit',
          icon: Icons.credit_card_outlined,
          count: dashboardDTO.unpaidCreditCount,
          color: Theme.of(context).colorScheme.primary,
          nextPage: const CreditlistPage(),
        ),
      ],
    );
  }

  Widget _buildQuickAccessCard({
    required String label,
    required IconData icon,
    int count = 0,
    Stream<int>? stream,
    required Color color,
    required Widget nextPage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildCard(int badgeCount) {
      return Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Helperfunctions.navigateThenWait(context, nextPage);
            if (mounted) await _refreshDashboardIfNeeded();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Badge(
                  isLabelVisible: badgeCount > 0,
                  label: Text('$badgeCount', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: Colors.red,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(icon, size: 24, color: color),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

    return Expanded(
      child: stream != null
          ? StreamBuilder<int>(stream: stream, initialData: count, builder: (context, snapshot) => buildCard(snapshot.data ?? 0))
          : buildCard(count),
    );
  }

  Widget _buildKpiGrid() {
    return Column(
      spacing: 12,
      children: [
        Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSalesCard()),
            Expanded(child: _buildBuyingCard()),
          ],
        ),
        Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildThruputCard()),
            Expanded(child: _buildPlacementCard()),
          ],
        ),
        Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildScanningCard()),
            Expanded(child: _buildExpansionCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildThruputCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'throughput');
    double buyingThruput = isSyncing ? 0 : dashboardDTO.buyingThruput;
    double thruputTarget = 8000;
    final missingThruput = (thruputTarget - buyingThruput).clamp(0.0, double.infinity);
    final percentage = thruputTarget == 0 ? 0.0 : (buyingThruput / thruputTarget);

    return _buildCardWrapper(
      title: 'Throughput',
      icon: Icons.speed_outlined,
      accent: accent,
      nextPage: ThruputPage(dashboardDTO: dashboardDTO),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: buyingThruput <= 0 ? 0.01 : buyingThruput, color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(
                        value: missingThruput <= 0 ? 0.01 : missingThruput,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 12,
                      ),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Actual', Helperfunctions.formatDoubleAmountForDisplay(buyingThruput), accent),
          _buildLegendRow('Missing', Helperfunctions.formatDoubleAmountForDisplay(missingThruput), colorScheme.onSurfaceVariant),
          _buildLegendRow('Target', Helperfunctions.formatDoubleAmountForDisplay(thruputTarget), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildPlacementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'placement');
    final int totalStores = dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount;
    double actual = isSyncing ? 0 : dashboardDTO.totalPlacementCount.toDouble();
    double missing = isSyncing ? 0 : (totalStores - dashboardDTO.totalPlacementCount).toDouble();
    double target = isSyncing ? 1 : dashboardDTO.totalHapiStores.toDouble();
    final percentage = target == 0 ? 0.0 : (actual / target);

    return _buildCardWrapper(
      title: 'Placement',
      icon: Icons.grid_view_outlined,
      accent: accent,
      nextPage: const PlacementlistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: actual <= 0 ? 0.01 : actual, color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(value: missing <= 0 ? 0.01 : missing, color: _mutedChartColor(context), showTitle: false, radius: 12),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Actual', actual.toStringAsFixed(0), accent),
          _buildLegendRow('Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow('Target', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildBuyingCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'buying');
    double buyingTarget = isSyncing ? 1 : (dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount).toDouble();
    double buyingCount = isSyncing ? 0 : dashboardDTO.buyingCount.toDouble();
    double nonBuyingCount = isSyncing ? 1 : dashboardDTO.nonBuyingCount.toDouble();
    final percentage = buyingTarget == 0 ? 0.0 : (buyingCount / buyingTarget);

    return _buildCardWrapper(
      title: 'Buying Stores',
      icon: Icons.shopping_cart_outlined,
      accent: accent,
      nextPage: const BuyinglistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: buyingCount <= 0 ? 0.01 : buyingCount, color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(
                        value: nonBuyingCount <= 0 ? 0.01 : nonBuyingCount,
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 12,
                      ),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Buying', buyingCount.toStringAsFixed(0), accent),
          _buildLegendRow('Non-Buying', nonBuyingCount.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow('Total Stores', buyingTarget.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildSalesCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'sales');
    const double target = 1000000;
    final double sales = dashboardDTO.totalInvoiceAmount;
    final double missing = (target - sales) < 0 ? 0 : (target - sales);
    final double percentage = target <= 0 ? 0 : (sales / target).clamp(0, 1);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    return _buildCardWrapper(
      title: 'Sales',
      icon: Icons.attach_money,
      accent: accent,
      nextPage: SalesPage(),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: sales <= 0 ? 0.01 : sales, color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(value: missing <= 0 ? 0.01 : missing, color: _mutedChartColor(context), showTitle: false, radius: 12),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Invoiced', currencyFormat.format(sales), accent),
          _buildLegendRow('Missing', currencyFormat.format(missing), colorScheme.onSurfaceVariant),
          _buildLegendRow('Target', currencyFormat.format(target), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildExpansionCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'expansion');
    const double target = 8;
    double opened = isSyncing ? 0 : dashboardDTO.totalExpansionCount.toDouble();
    double missing = (target - opened).clamp(0.0, double.infinity);
    final percentage = target == 0 ? 0.0 : (opened / target);

    return _buildCardWrapper(
      title: 'Expansion',
      icon: Icons.trending_up_outlined,
      accent: accent,
      nextPage: const ExpansionPage(),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: opened <= 0 ? 0.01 : opened, color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(value: missing <= 0 ? 0.01 : missing, color: _mutedChartColor(context), showTitle: false, radius: 12),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Opened', opened.toStringAsFixed(0), accent),
          _buildLegendRow('Missing', missing.toStringAsFixed(0), colorScheme.onSurfaceVariant),
          _buildLegendRow('Target', target.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildScanningCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = _metricColor(context, 'scanning');
    final scanned = isSyncing ? 0 : dashboardDTO.totalScanCount;
    final notScanned = isSyncing ? 0 : dashboardDTO.totalNotScannedCount;
    final total = scanned + notScanned;
    final percentage = total == 0 ? 0.0 : scanned / total;

    return _buildCardWrapper(
      title: 'Scanning',
      icon: Icons.qr_code_scanner_outlined,
      accent: accent,
      nextPage: const ScanninglistPage(),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: scanned <= 0 ? 0.01 : scanned.toDouble(), color: accent, showTitle: false, radius: 14),
                      PieChartSectionData(
                        value: notScanned <= 0 ? 0.01 : notScanned.toDouble(),
                        color: _mutedChartColor(context),
                        showTitle: false,
                        radius: 12,
                      ),
                    ],
                  ),
                ),
                Text(NumberFormat('0%').format(percentage), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendRow('Scanned', scanned.toString(), accent),
          _buildLegendRow('Not Scanned', notScanned.toString(), colorScheme.onSurfaceVariant),
          _buildLegendRow('Total', total.toString(), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildCardWrapper({required String title, required IconData icon, required Widget child, required Widget nextPage, Color? accent}) {
    final colorScheme = Theme.of(context).colorScheme;
    final cardAccent = accent ?? colorScheme.primary;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cardAccent.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Helperfunctions.navigateThenWait(context, nextPage);
          if (mounted) await _refreshDashboardIfNeeded();
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: cardAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Icon(icon, size: 16, color: cardAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                ],
              ),
              const Divider(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
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
                  _currentUser?.username ?? (isDealer ? 'Dealer' : 'Salesman'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(_currentUser?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),

          // 1. Operations
          _buildDrawerSectionHeader('Operations'),
          StreamBuilder<int>(
            stream: _merchBlitzCountStream,
            builder: (context, snapshot) {
              return _buildDrawerItem(Icons.campaign_outlined, 'Merch Blitz', const MerchBlitzListPage(), badgeCount: snapshot.data ?? 0);
            },
          ),
          StreamBuilder<int>(
            stream: _tasksCountStream,
            builder: (context, snapshot) {
              return _buildDrawerItem(Icons.task_alt_outlined, 'Tasks', const TaskListPage(), badgeCount: snapshot.data ?? 0);
            },
          ),
          _buildDrawerItem(Icons.assignment_return_outlined, 'Returns', const ReturnlistPage(), badgeCount: dashboardDTO.returnedDeliveryCount),
          _buildDrawerItem(Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
          _buildDrawerItem(Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
          _buildDrawerItem(Icons.today_outlined, 'End of Day Report', const EndofdayPage()),
          _buildDrawerItem(Icons.swap_horiz_outlined, 'Transactions', const TransactionListPage(storeName: '')),

          const Divider(indent: 16, endIndent: 16),

          // 2. KPI Section
          _buildDrawerSectionHeader('KPI Section'),
          _buildDrawerItem(Icons.attach_money, 'Sales', const SalesPage()),
          _buildDrawerItem(Icons.shopping_cart_outlined, 'Buying Stores', const BuyinglistPage()),
          _buildDrawerItem(Icons.speed_outlined, 'Throughput', ThruputPage(dashboardDTO: dashboardDTO)),
          _buildDrawerItem(Icons.grid_view_outlined, 'Placement', const PlacementlistPage()),
          _buildDrawerItem(Icons.qr_code_scanner_outlined, 'Scanning', const ScanninglistPage()),
          _buildDrawerItem(Icons.trending_up_outlined, 'Expansion', const ExpansionPage()),

          const Divider(indent: 16, endIndent: 16),

          // 3. Settings Section
          _buildDrawerSectionHeader('Settings Section'),
          _buildDrawerItem(
            Icons.sync_rounded,
            'Sync Data',
            null,
            onTap: () {
              if (!isSyncing) syncDashboard();
            },
          ),
          _buildDrawerItem(Icons.storefront_outlined, 'Hapi Stores', const HapiStoreListPage()),
          if (isDealer)
            _buildDrawerItem(Icons.warehouse_outlined, 'Inventory', const InventoryPage()),
          if (isDealer)
            _buildDrawerItem(Icons.inventory_2_outlined, 'Selecta Products', const SelectaProductsPage()),
          if (isDealer)
            _buildDrawerItem(Icons.inventory_2_outlined, 'Other Products', const OtherProductsPage()),
          _buildDrawerItem(Icons.map_outlined, 'Journey Plan (PJP)', const PjpListPage(), badgeCount: dashboardDTO.pendingPjpCount),
          _buildDrawerItem(Icons.history_outlined, 'Audit Logs', const TransactionLogPage()),
          _buildDrawerItem(Icons.cloud_upload_outlined, 'Upload Error Logs', null, onTap: _handleUploadErrorLogs),
          _buildDrawerItem(Icons.settings_outlined, 'Configurations', const ConfigurationPage()),

          const Divider(indent: 16, endIndent: 16),

          // 4. Logout
          _buildDrawerItem(Icons.logout_rounded, 'Logout', null, isLogout: true),
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

  Widget _buildDrawerSectionHeader(String title) {
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
    IconData icon,
    String title,
    Widget? nextPage, {
    bool isLogout = false,
    int badgeCount = 0,
    Color? badgeColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : null, size: 22),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isLogout ? Colors.red : null),
      ),
      trailing: badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
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
          onLogout();
        } else if (nextPage != null) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => nextPage));
          if (mounted) await _refreshDashboardIfNeeded();
        }
      },
    );
  }

  Color _mutedChartColor(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  Color _metricColor(BuildContext context, String metric) {
    final colorScheme = Theme.of(context).colorScheme;

    return switch (metric) {
      'sales' => const Color(0xFF15803D),
      'buying' => const Color(0xFF2563EB),
      'throughput' => const Color(0xFF7C3AED),
      'placement' => const Color(0xFF0891B2),
      'scanning' => const Color(0xFFD97706),
      'expansion' => const Color(0xFF0F766E),
      _ => colorScheme.primary,
    };
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
            icon: isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync_rounded, color: Colors.white),
            onPressed: isSyncing ? null : syncDashboard,
            tooltip: 'Sync Dashboard',
          ),
        ],
      ),
      drawer: _buildDrawer(),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              // 1. User Welcome & Last Sync Banner
              _buildWelcomeBanner(),

              // 2. Quick Access Section
              _buildSectionHeader('Quick Access', 'Pending deliveries, purchase orders, and credits'),
              _buildQuickAccessGrid(),

              // 3. Operational Metrics / KPI Section
              _buildSectionHeader('Performance KPIs', 'Sales, throughput, and store coverage'),
              _buildKpiGrid(),
            ],
          ),
        ),
      ),
    );
  }
}
