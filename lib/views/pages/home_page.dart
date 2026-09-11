import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/dashboard_controller.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/kpi/buyinglist_page.dart';
import 'package:flutter_app/views/pages/creditlist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
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
  String lastSyncDateTime = '';
  bool isDealer = false;
  bool isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Home'),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            drawerHeader(),

            drawerMenu(Icons.home, 'Deliveries', DeliveryListPage(), notifyCount: dashboardDTO.pendingDeliveryCount),
            drawerMenu(Icons.home, 'Credit', CreditlistPage(), notifyCount: dashboardDTO.unpaidCreditCount),
            drawerMenu(Icons.home, 'Return', ReturnlistPage(), notifyCount: dashboardDTO.returnedDeliveryCount),
            drawerMenu(Icons.home, 'Bad Orders', BadOrderlistPage()),
            drawerMenu(Icons.home, 'Expenses', ExpenselistPage()),
            drawerMenu(Icons.home, 'End of Day Report', EndofdayPage()),
            drawerMenu(Icons.home, 'Transactions', TransactionListPage(storeName: '')),

            Divider(),

            drawerMenu(Icons.home, 'Logs', TransactionLogPage()),
            drawerMenu(Icons.home, 'Hapi Stores', HapiStoreListPage()),
            //homeMenu(Icons.home, 'Products', SettingsPage()), // route to product page

            Divider(),

            //homeMenu(Icons.settings_sharp, 'Settings', SettingsPage()),
            drawerMenu(Icons.logout_sharp, 'Logout', SettingsPage(), isLogout: true),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 20),
          child: Column(
            spacing: 20,
            children: [
              dashboardLastSync(),
              Row(
                spacing: 10,
                children: [
                  dashboardItem(dashBoardSales(), nextPage: BuyinglistPage()),
                  dashboardItem(dashBoardThruput(), nextPage: ThruputPage(dashboardDTO: dashboardDTO)),
                ],
              ),
              Row(
                spacing: 10,
                children: [
                  dashboardItem(dashboardBuying(), nextPage: BuyinglistPage()),
                  dashboardItem(dashboardScanning(), nextPage: BuyinglistPage()),
                ],
              ),
              Row(
                spacing: 10,
                children: [
                  dashboardItem(dashBoardCOTC(), nextPage: BuyinglistPage()),
                  dashboardItem(dashBoardExpansion(), nextPage: BuyinglistPage()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void prefetchData() async {
    // Check if the user is a dealer
    isDealer = await KVariables.getIsDealer();

    // Sync DashBoard
    syncDashboard();
  }

  Future<void> syncDashboard() async {
    showLoading(true);
    setState(() {
      isSyncing = true;
      dashboardDTO = DashboardDTO.empty();
    });

    dashboardDTO = await DashboardController.getLatestDashboardData();
    lastSyncDateTime = await DashboardController.getLastSync();

    isSyncing = false;
    showLoading(false);
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

  Widget dashboardItem(Widget? dashboardContent, {required dynamic nextPage}) {
    return Expanded(
      child: Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white, // Note: put color inside BoxDecoration if using decoration
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: InkWell(
          onTap: () async {
            await Helperfunctions.navigateThenWait(context, nextPage);
            syncDashboard();
          },
          child: Padding(padding: const EdgeInsets.all(8.0), child: dashboardContent),
        ),
      ),
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
    return Column(spacing: 5, children: [KForms.textTitle('Sales')]);
  }

  Widget dashBoardThruput() {
    double buyingThruput = 0;
    double thruputTarget = 8000;

    // for UI loading purposes
    if (!isSyncing) {
      buyingThruput = dashboardDTO.buyingThruput;
    }

    return Column(
      spacing: 5,
      children: [
        KForms.textTitle('Thruput'),
        KForms.pieChart(
          listData: [
            PieChartSectionData(value: buyingThruput, color: Colors.green, showTitle: false),
            PieChartSectionData(value: thruputTarget - buyingThruput, color: Colors.red, showTitle: false),
          ],
          title: NumberFormat('0.00%').format(buyingThruput / thruputTarget),
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

    return Column(
      spacing: 5,
      children: [
        KForms.textTitle('Buying'),
        KForms.pieChart(
          listData: [
            PieChartSectionData(value: buyingCount, color: Colors.green, showTitle: false),
            PieChartSectionData(value: nonBuyingCount, color: Colors.red, showTitle: false),
          ],
          title: NumberFormat('0.00%').format(buyingCount / buyingTarget),
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
    return Column(spacing: 5, children: [KForms.textTitle('Scanning')]);
  }

  Widget dashBoardCOTC() {
    return Column(spacing: 5, children: [KForms.textTitle('COTC')]);
  }

  Widget dashBoardExpansion() {
    return Column(spacing: 5, children: [KForms.textTitle('Expansion')]);
  }

  void showLoading(bool showLoading) async {
    if (mounted) await Helperfunctions.showLoading(context: context, showLoading: showLoading);
    if (!showLoading) setState(() {});
  }
}
