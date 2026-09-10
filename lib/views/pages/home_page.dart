import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/home_service.dart';
import 'package:flutter_app/views/pages/buyinglist_page.dart';
import 'package:flutter_app/views/pages/creditlist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
import 'package:flutter_app/views/pages/endofday_page.dart';
import 'package:flutter_app/views/pages/expenselist_page.dart';
import 'package:flutter_app/views/pages/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/badorderlist_page.dart';
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
  DeliveryService dbDelivery = DeliveryService();
  HomeService homeService = HomeService();
  DashboardDto? dashboardDto;
  int? pendingDeliveryCount;
  int? unpaidCreditCount;
  int? returnedDeliveryCount;
  bool isDealer = false;
  String? lastSyncDateTime;
  bool isFirstLoad = false;
  bool isSyncing = false;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  Widget build(BuildContext context) {
    return isFirstLoad
        ? Center(child: CircularProgressIndicator())
        : Scaffold(
            appBar: KForms.appbar('Home'),
            drawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  drawerHeader(),

                  homeMenu(Icons.home, 'Deliveries', DeliveryListPage(), notifyCount: pendingDeliveryCount),
                  homeMenu(Icons.home, 'Credit', CreditlistPage(), notifyCount: unpaidCreditCount),
                  homeMenu(Icons.home, 'Return', ReturnlistPage(), notifyCount: returnedDeliveryCount),
                  homeMenu(Icons.home, 'Bad Orders', BadOrderlistPage()),
                  homeMenu(Icons.home, 'Expenses', ExpenselistPage()),
                  homeMenu(Icons.home, 'End of Day Report', EndofdayPage()),
                  homeMenu(Icons.home, 'Transactions', TransactionListPage()),

                  Divider(),

                  homeMenu(Icons.home, 'Logs', TransactionLogPage()),
                  homeMenu(Icons.home, 'Hapi Stores', HapiStoreListPage()),
                  //homeMenu(Icons.home, 'Products', SettingsPage()), // route to product page

                  Divider(),

                  //homeMenu(Icons.settings_sharp, 'Settings', SettingsPage()),
                  homeMenu(Icons.logout_sharp, 'Logout', SettingsPage(), isLogout: true),
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
                        dashboardItem(dashBoardThruput(), nextPage: BuyinglistPage()),
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
    setState(() => isFirstLoad = true);

    dashboardDto = await homeService.getDataFromSharedPrefs();
    lastSyncDateTime = await HomeService.getLastSyncDateTime();

    setState(() => isFirstLoad = false);
  }

  Future<void> syncData() async {
    isSyncing = true;
    dashboardDto = DashboardDto.empty();
    setState(() => Helperfunctions.showLoadingDialog(context: context, showLoading: true));

    // Update last sync time
    await homeService.saveLastSyncDateTime();
    lastSyncDateTime = await HomeService.getLastSyncDateTime();

    unpaidCreditCount = await dbDelivery.getCountDeliveryWithCreditNotYetPaid();
    pendingDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(DeliveryStatus.pending);
    returnedDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(DeliveryStatus.returned);
    isDealer = await KVariables.getIsDealer();

    // DASHBOARD: Buying - Check for buying and non buying hapi stores.
    var listStores = await homeService.getListOfBuyingAndNonBuyingStores();
    var listBuyingStores = listStores.where((store) => store.isBuying!);
    dashboardDto!.buyingCount = listBuyingStores.length;
    dashboardDto!.nonBuyingCount = listStores.length - dashboardDto!.buyingCount;

    // DASHBOARD: Thruput of buying stores
    double totalAmount = 0;
    for (var buying in listBuyingStores) {
      totalAmount += buying.deliveredAmount!;
    }
    dashboardDto!.buyingThruput = totalAmount / listBuyingStores.length;

    // save the dashboardDto to shared preferences
    await homeService.saveDataToSharedPrefs(dashboardDto!);

    setState(() => Helperfunctions.showLoadingDialog(context: context, showLoading: false));
    isSyncing = false;
  }

  void onLogout() {
    KForms.alertDialogConfirm('Logout', 'Are you sure you want to log out?', context, () async {
      try {
        setState(() => Helperfunctions.showLoadingDialog(context: context, showLoading: true));
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
        setState(() => Helperfunctions.showLoadingDialog(context: context, showLoading: false));
      }
    });
  }

  ListTile homeMenu(IconData icon, String title, Widget nextPage, {int? notifyCount, bool isLogout = false}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () async {
        Navigator.pop(context); // close the drawer
        if (isLogout) {
          onLogout();
        } else {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => nextPage));
          syncData();
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
            syncData();
          },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: dashboardDto != null
                ? dashboardContent
                : Center(
                    child: Text('Please sync data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
          ),
        ),
      ),
    );
  }

  Widget dashboardLastSync() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        KForms.textDescriptionString('$lastSyncDateTime'),
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: () {
            syncData();
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

    if (dashboardDto != null) {
      buyingThruput = dashboardDto!.buyingThruput;
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

    if (dashboardDto != null) {
      buyingTarget = (dashboardDto!.buyingCount + dashboardDto!.nonBuyingCount).toDouble();
      buyingCount = dashboardDto!.buyingCount.toDouble();
      nonBuyingCount = dashboardDto!.nonBuyingCount.toDouble();
    }

    // for UI loading purposes
    if (isSyncing) {
      dashboardDto!.nonBuyingCount = 1; // for UI purposes
      buyingTarget = 1;
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
}
