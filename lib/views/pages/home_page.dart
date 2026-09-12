import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/badorderlist_page.dart';
import 'package:flutter_app/views/pages/creditlist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
import 'package:flutter_app/views/pages/endofday_page.dart';
import 'package:flutter_app/views/pages/expenselist_page.dart';
import 'package:flutter_app/views/pages/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/kpi/buyinglist_page.dart';
import 'package:flutter_app/views/pages/kpi/thruput_page.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/pages/returnlist_page.dart';
import 'package:flutter_app/views/pages/transactionlist_page.dart';
import 'package:flutter_app/views/pages/transactionlog_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DashboardDTO dashboardDTO = DashboardDTO.empty();
  bool isDealer = false;
  bool isSyncing = false;
  String lastSyncDateTime = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
  }

  void prefetchData() async {
    isDealer = await KVariables.getIsDealer();
    syncDashboard();
  }

  Future<void> syncDashboard() async {
    if (!mounted) return;

    setState(() {
      isSyncing = true;
      dashboardDTO = DashboardDTO.empty();
    });

    dashboardDTO = await DashboardController.getLatestDashboardData();
    lastSyncDateTime = await DashboardController.getLastSync();

    if (mounted) {
      setState(() {
        isSyncing = false;
      });
    }
  }

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
        await authService.value.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          ShowMessage.error(context, e.message ?? 'There was a problem upon signing out');
        }
      }
    }
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
              _buildSectionHeader('Quick Access', 'Pending deliveries, credits, and returns'),
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

  Widget _buildWelcomeBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    final user = authService.value.currentUser;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.waving_hand_rounded, color: colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, ${user?.displayName ?? 'Salesman'}!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  lastSyncDateTime.isNotEmpty ? 'Last synced: $lastSyncDateTime' : 'Ready to take orders',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: (isDealer ? Colors.blue : Colors.teal).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              isDealer ? 'Dealer' : 'Salesman',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDealer ? Colors.blue.shade800 : Colors.teal.shade800),
            ),
          ),
        ],
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
          color: Colors.blue,
          nextPage: const DeliveryListPage(),
        ),
        _buildQuickAccessCard(
          label: 'Credit',
          icon: Icons.credit_card_outlined,
          count: dashboardDTO.unpaidCreditCount,
          color: Colors.orange,
          nextPage: const CreditlistPage(),
        ),
        _buildQuickAccessCard(
          label: 'Returns',
          icon: Icons.assignment_return_outlined,
          count: dashboardDTO.returnedDeliveryCount,
          color: Colors.purple,
          nextPage: const ReturnlistPage(),
        ),
      ],
    );
  }

  Widget _buildQuickAccessCard({
    required String label,
    required IconData icon,
    required int count,
    required MaterialColor color,
    required Widget nextPage,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Card(
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
            if (mounted) syncDashboard();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: color.shade700,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(icon, size: 24, color: color.shade800),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
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
            Expanded(child: _buildThruputCard()),
            Expanded(child: _buildBuyingCard()),
          ],
        ),
        Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildBlankCard(title: 'Sales Volume', icon: Icons.point_of_sale_outlined),
            ),
            Expanded(
              child: _buildBlankCard(title: 'Store Scanning', icon: Icons.qr_code_scanner_outlined),
            ),
          ],
        ),
        Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildBlankCard(title: 'Placement', icon: Icons.grid_view_outlined),
            ),
            Expanded(
              child: _buildBlankCard(title: 'Expansion', icon: Icons.trending_up_outlined),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThruputCard() {
    final colorScheme = Theme.of(context).colorScheme;
    double buyingThruput = isSyncing ? 0 : dashboardDTO.buyingThruput;
    double thruputTarget = 8000;
    final missingThruput = (thruputTarget - buyingThruput).clamp(0.0, double.infinity);
    final percentage = thruputTarget == 0 ? 0.0 : (buyingThruput / thruputTarget);

    return _buildCardWrapper(
      title: 'Throughput',
      icon: Icons.speed_outlined,
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
                      PieChartSectionData(value: buyingThruput <= 0 ? 0.01 : buyingThruput, color: Colors.green, showTitle: false, radius: 14),
                      PieChartSectionData(
                        value: missingThruput <= 0 ? 0.01 : missingThruput,
                        color: Colors.red.shade300,
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
          _buildLegendRow('Actual', Helperfunctions.formatDoubleAmountForDisplay(buyingThruput), Colors.green),
          _buildLegendRow('Missing', Helperfunctions.formatDoubleAmountForDisplay(missingThruput), Colors.red),
          _buildLegendRow('Target', Helperfunctions.formatDoubleAmountForDisplay(thruputTarget), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildBuyingCard() {
    final colorScheme = Theme.of(context).colorScheme;
    double buyingTarget = isSyncing ? 1 : (dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount).toDouble();
    double buyingCount = isSyncing ? 0 : dashboardDTO.buyingCount.toDouble();
    double nonBuyingCount = isSyncing ? 1 : dashboardDTO.nonBuyingCount.toDouble();
    final percentage = buyingTarget == 0 ? 0.0 : (buyingCount / buyingTarget);

    return _buildCardWrapper(
      title: 'Buying Stores',
      icon: Icons.shopping_cart_outlined,
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
                      PieChartSectionData(value: buyingCount <= 0 ? 0.01 : buyingCount, color: Colors.green, showTitle: false, radius: 14),
                      PieChartSectionData(
                        value: nonBuyingCount <= 0 ? 0.01 : nonBuyingCount,
                        color: Colors.red.shade300,
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
          _buildLegendRow('Buying', buyingCount.toStringAsFixed(0), Colors.green),
          _buildLegendRow('Non-Buying', nonBuyingCount.toStringAsFixed(0), Colors.red),
          _buildLegendRow('Total Stores', buyingTarget.toStringAsFixed(0), colorScheme.onSurface),
        ],
      ),
    );
  }

  Widget _buildBlankCard({required String title, required IconData icon, Widget? nextPage}) {
    return _buildCardWrapper(title: title, icon: icon, nextPage: nextPage ?? const BuyinglistPage(), child: const SizedBox(height: 180));
  }

  Widget _buildCardWrapper({required String title, required IconData icon, required Widget child, required Widget nextPage}) {
    final colorScheme = Theme.of(context).colorScheme;

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
          if (mounted) syncDashboard();
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: colorScheme.primary),
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
    final user = authService.value.currentUser;

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
                  user?.displayName ?? 'User',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(user?.email ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),

          // Drawer Navigation Items
          _buildDrawerItem(Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
          _buildDrawerItem(Icons.receipt_long_outlined, 'Expenses', const ExpenselistPage()),
          _buildDrawerItem(Icons.today_outlined, 'End of Day Report', const EndofdayPage()),
          _buildDrawerItem(Icons.swap_horiz_outlined, 'Transactions', const TransactionListPage(storeName: '')),

          const Divider(indent: 16, endIndent: 16),

          _buildDrawerItem(Icons.history_outlined, 'Audit Logs', const TransactionLogPage()),
          _buildDrawerItem(Icons.storefront_outlined, 'Hapi Stores', const HapiStoreListPage()),

          const Divider(indent: 16, endIndent: 16),

          _buildDrawerItem(Icons.logout_rounded, 'Sign Out', null, isLogout: true),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, Widget? nextPage, {bool isLogout = false}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? Colors.red : null, size: 22),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isLogout ? Colors.red : null),
      ),
      onTap: () async {
        Navigator.pop(context);
        if (isLogout) {
          onLogout();
        } else if (nextPage != null) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => nextPage));
          syncDashboard();
        }
      },
    );
  }
}
