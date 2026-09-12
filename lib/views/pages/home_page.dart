import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/creditlist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
import 'package:flutter_app/views/pages/kpi/buyinglist_page.dart';
import 'package:flutter_app/views/pages/endofday_page.dart';
import 'package:flutter_app/views/pages/expenselist_page.dart';
import 'package:flutter_app/views/pages/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/badorderlist_page.dart';
import 'package:flutter_app/views/pages/kpi/thruput_page.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/pages/others/settings_page.dart';
import 'package:flutter_app/views/pages/returnlist_page.dart';
import 'package:flutter_app/views/pages/transactionlist_page.dart';
import 'package:flutter_app/views/pages/transactionlog_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
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

  static const Color _pageBackground = Color(0xFFF5F7FB);
  static const Color _primaryColor = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
  }

  void prefetchData() async {
    // Check if the user is a dealer
    isDealer = await KVariables.getIsDealer();

    // Sync DashBoard
    syncDashboard();
  }

  Future<void> syncDashboard() async {
    //showLoading(true);

    if (!mounted) return;

    setState(() {
      isSyncing = true;
      dashboardDTO = DashboardDTO.empty();
    });

    dashboardDTO = await DashboardController.getLatestDashboardData();
    lastSyncDateTime = await DashboardController.getLastSync();

    isSyncing = false;
    if (mounted) setState(() {});
    //showLoading(false);
  }

  void onLogout() {
    KForms.alertDialogConfirm('Logout', 'Are you sure you want to log out?', context, () async {
      try {
        showLoading(true);
        await authService.value.signOut();

        if (mounted) {
          // ShowMessage.success(context, 'Successfully logged out!');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const AuthPage()),
            (Route<dynamic> route) => false,
          ); // This removes all previous routes
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          ShowMessage.error(context, e.message ?? 'There was a problem upon signing out');
        }
        showLoading(false);
      }
    });
  }

  ListTile drawerMenu(IconData icon, String title, Widget nextPage, {int? notifyCount, bool isLogout = false}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () async {
        Navigator.pop(context); // close the drawer
        if (isLogout) {
          onLogout();
        } else {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => nextPage));
          syncDashboard();
        }
      },
      trailing: notifyCount == null || notifyCount == 0
          ? null
          : ClipOval(
              child: Container(
                color: Colors.red,
                width: 20,
                height: 20,
                child: Center(
                  child: Text(notifyCount.toString(), style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
    );
  }

  Widget drawerHeader() {
    return UserAccountsDrawerHeader(
      accountName: Text(authService.value.currentUser!.displayName ?? ''),
      accountEmail: Text(authService.value.currentUser!.email!),
      currentAccountPicture: CircleAvatar(
        child: ClipOval(child: Image.asset('assets/images/profile.jpg', width: 90, height: 90, fit: BoxFit.cover)),
      ),
      decoration: BoxDecoration(
        color: Colors.blue,
        image: DecorationImage(image: AssetImage('assets/images/profilebackground.jpg'), fit: BoxFit.cover),
      ),
    );
  }

  Widget dashboardItem(
    Widget dashboardContent, {
    required Widget nextPage,
    required IconData icon,
    String? tooltip,
    Color accentColor = _primaryColor,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        label: 'Click to open',
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: _cardDecoration(accentColor: accentColor),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              splashColor: accentColor.withValues(alpha: 0.12),
              highlightColor: accentColor.withValues(alpha: 0.05),
              onTap: () async {
                await Helperfunctions.navigateThenWait(context, nextPage);

                if (mounted) {
                  syncDashboard();
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 280),
                child: Stack(
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 16), child: dashboardContent),

                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: accentColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget dashboardMiniItem(Widget dashboardContent, {required dynamic nextPage, Color accentColor = _primaryColor}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () async {
            await Helperfunctions.navigateThenWait(context, nextPage);
            if (mounted) syncDashboard();
          },
          child: Ink(
            height: 112,
            decoration: _cardDecoration(accentColor: accentColor),
            child: Padding(padding: const EdgeInsets.all(10), child: dashboardContent),
          ),
        ),
      ),
    );
  }

  Widget dashboardMiniContent({required IconData icon, required String label, int notificationCount = 0, Color color = _primaryColor}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Badge(
          isLabelVisible: notificationCount > 0,
          label: Text(notificationCount.toString(), style: const TextStyle(fontSize: 11)),
          child: CircleAvatar(
            radius: 23,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, size: 26, color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF263238)),
        ),
      ],
    );
  }

  Widget dashboardLastSync() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        KForms.textDescriptionString(lastSyncDateTime),
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            syncDashboard();
          },
        ),
      ],
    );
  }

  Widget dashBoardSales() {
    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Sales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))],
    );
  }

  Widget dashBoardThruput() {
    double buyingThruput = 0;
    double thruputTarget = 8000;

    // for UI loading purposes
    if (!isSyncing) {
      buyingThruput = dashboardDTO.buyingThruput;
    }

    final percentage = thruputTarget == 0 ? 0 : buyingThruput / thruputTarget;

    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Thruput', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        KForms.pieChart(
          listData: [
            PieChartSectionData(value: buyingThruput, color: Colors.green, showTitle: false),
            PieChartSectionData(value: thruputTarget - buyingThruput, color: Colors.red, showTitle: false),
          ],
          title: NumberFormat('0.00%').format(percentage),
        ),
        Divider(),
        Column(
          children: [
            Row(
              children: [
                Text('Actual: ', style: TextStyle(color: Colors.green)),
                Spacer(),
                Text(Helperfunctions.formatDoubleAmountForDisplay(buyingThruput)),
              ],
            ),
            Row(
              children: [
                Text('Missing: ', style: TextStyle(color: Colors.red)),
                Spacer(),
                Text(Helperfunctions.formatDoubleAmountForDisplay(thruputTarget - buyingThruput)),
              ],
            ),
            Row(
              children: [
                Text('Target: ', style: TextStyle(color: Colors.black)),
                Spacer(),
                Text(Helperfunctions.formatDoubleAmountForDisplay(thruputTarget)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget dashboardBuying() {
    double buyingTarget = 0;
    double buyingCount = 0;
    double nonBuyingCount = 0;

    if (isSyncing) {
      // for UI loading purposes
      nonBuyingCount = 1;
      buyingTarget = 1;
    } else {
      buyingTarget = (dashboardDTO.buyingCount + dashboardDTO.nonBuyingCount).toDouble();
      buyingCount = dashboardDTO.buyingCount.toDouble();
      nonBuyingCount = dashboardDTO.nonBuyingCount.toDouble();
    }

    final percentage = buyingTarget == 0 ? 0 : buyingCount / buyingTarget;

    return Column(
      spacing: 5,
      children: [
        KForms.textTitle('Buying'),
        KForms.pieChart(
          listData: [
            PieChartSectionData(value: buyingCount, color: Colors.green, showTitle: false),
            PieChartSectionData(value: nonBuyingCount, color: Colors.red, showTitle: false),
          ],
          title: NumberFormat('0.00%').format(percentage),
        ),
        Divider(),
        Column(
          children: [
            Row(
              children: [
                Text('Buying: ', style: TextStyle(color: Colors.green)),
                Spacer(),
                Text('$buyingCount'),
              ],
            ),
            Row(
              children: [
                Text('Non Buying: ', style: TextStyle(color: Colors.red)),
                Spacer(),
                Text('$nonBuyingCount'),
              ],
            ),
            Row(
              children: [
                Text('Total: ', style: TextStyle(color: Colors.black)),
                Spacer(),
                Text('$buyingTarget '),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget dashboardScanning() {
    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Scanning', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))],
    );
  }

  Widget dashBoardCOTC() {
    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('COTC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))],
    );
  }

  Widget dashBoardExpansion() {
    return Column(
      spacing: 5,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Expansion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))],
    );
  }

  void showLoading(bool showLoading) async {
    if (mounted) {
      await Helperfunctions.showLoading(context: context, showLoading: showLoading);
      if (!showLoading) setState(() {});
    }
  }

  BoxDecoration _cardDecoration({Color? accentColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border(top: BorderSide(color: accentColor ?? _primaryColor, width: 4)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 8))],
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF172033)),
              ),
              if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))],
            ],
          ),
        ),
      ],
    );
  }

  Widget _welcomeHeader() {
    final user = authService.value.currentUser;
    final name = user?.displayName?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F46E5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: _primaryColor.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person_outline, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back${name == null || name.isEmpty ? '' : ','}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                Text(
                  name?.isNotEmpty == true ? name! : 'User',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: isSyncing ? null : syncDashboard,
            icon: const Icon(Icons.sync, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Dashboard'),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            drawerHeader(),

            drawerMenu(Icons.assignment_late_outlined, 'Bad Orders', BadOrderlistPage()),
            drawerMenu(Icons.receipt_long_outlined, 'Expenses', ExpenselistPage()),
            drawerMenu(Icons.today_outlined, 'End of Day Report', EndofdayPage()),
            drawerMenu(Icons.swap_horiz_outlined, 'Transactions', TransactionListPage(storeName: '')),

            const Divider(indent: 16, endIndent: 16),

            drawerMenu(Icons.history_outlined, 'Logs', TransactionLogPage()),
            drawerMenu(Icons.storefront_outlined, 'Hapi Stores', HapiStoreListPage()),

            const Divider(indent: 16, endIndent: 16),

            drawerMenu(Icons.logout_rounded, 'Logout', SettingsPage(), isLogout: true),
          ],
        ),
      ),
      body: Container(
        color: _pageBackground,
        child: RefreshIndicator(
          onRefresh: syncDashboard,
          color: _primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeHeader(),
                const SizedBox(height: 24),

                _sectionTitle('Quick access', subtitle: 'Monitor your pending activities'),
                const SizedBox(height: 12),

                Row(
                  spacing: 10,
                  children: [
                    dashboardMiniItem(
                      dashboardMiniContent(
                        icon: Icons.local_shipping_outlined,
                        label: 'Deliveries',
                        notificationCount: dashboardDTO.pendingDeliveryCount,
                        color: Colors.blue,
                      ),
                      nextPage: DeliveryListPage(),
                      accentColor: Colors.blue,
                    ),

                    dashboardMiniItem(
                      dashboardMiniContent(
                        icon: Icons.credit_card_outlined,
                        label: 'Credit',
                        notificationCount: dashboardDTO.unpaidCreditCount,
                        color: Colors.orange,
                      ),
                      nextPage: CreditlistPage(),
                      accentColor: Colors.orange,
                    ),

                    dashboardMiniItem(
                      dashboardMiniContent(
                        icon: Icons.assignment_return_outlined,
                        label: 'Returns',
                        notificationCount: dashboardDTO.returnedDeliveryCount,
                        color: Colors.purple,
                      ),
                      nextPage: ReturnlistPage(),
                      accentColor: Colors.purple,
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                _sectionTitle('Performance', subtitle: 'Your latest operational metrics'),
                const SizedBox(height: 12),

                Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    dashboardItem(
                      dashBoardSales(),
                      nextPage: BuyinglistPage(),
                      icon: Icons.point_of_sale_outlined,
                      tooltip: 'Open sales',
                      accentColor: Colors.indigo,
                    ),
                    dashboardItem(
                      dashBoardThruput(),
                      nextPage: ThruputPage(dashboardDTO: dashboardDTO),
                      icon: Icons.speed_outlined,
                      tooltip: 'Open throughput',
                      accentColor: Colors.green,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    dashboardItem(
                      dashboardBuying(),
                      nextPage: BuyinglistPage(),
                      icon: Icons.shopping_cart_outlined,
                      tooltip: 'Open buying',
                      accentColor: Colors.orange,
                    ),
                    dashboardItem(
                      dashboardScanning(),
                      nextPage: BuyinglistPage(),
                      icon: Icons.qr_code_scanner_outlined,
                      tooltip: 'Open scanning',
                      accentColor: Colors.teal,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    dashboardItem(
                      dashBoardCOTC(),
                      nextPage: BuyinglistPage(),
                      icon: Icons.storefront_outlined,
                      tooltip: 'Open COTC',
                      accentColor: Colors.purple,
                    ),
                    dashboardItem(
                      dashBoardExpansion(),
                      nextPage: BuyinglistPage(),
                      icon: Icons.trending_up_outlined,
                      tooltip: 'Open expansion',
                      accentColor: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
