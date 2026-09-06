import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/creditlist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
import 'package:flutter_app/views/pages/endofday_page.dart';
import 'package:flutter_app/views/pages/expenselist_page.dart';
import 'package:flutter_app/views/pages/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/badorderlist_page.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/pages/others/settings_page.dart';
import 'package:flutter_app/views/pages/returnlist_page.dart';
import 'package:flutter_app/views/pages/transactionlog_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DeliveryService dbDelivery = DeliveryService();
  int? pendingDeliveryCount;
  int? unpaidCreditCount;
  int? returnedDeliveryCount;
  bool isLoading = true;
  bool isDealer = false;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? Center(child: CircularProgressIndicator())
        : Scaffold(
            appBar: KForms.appbar('Home'),
            drawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  drawerHeader(),

                  homeMenu(
                    Icons.home,
                    'Deliveries',
                    DeliveryListPage(),
                    notifyCount: pendingDeliveryCount,
                  ),
                  homeMenu(
                    Icons.home,
                    'Credit',
                    CreditlistPage(),
                    notifyCount: unpaidCreditCount,
                  ),
                  homeMenu(
                    Icons.home,
                    'Return',
                    ReturnlistPage(),
                    notifyCount: returnedDeliveryCount,
                  ),
                  homeMenu(Icons.home, 'Bad Orders', BadOrderlistPage()),
                  homeMenu(Icons.home, 'Expenses', ExpenselistPage()),
                  homeMenu(Icons.home, 'End of Day Report', EndofdayPage()),

                  Divider(),

                  homeMenu(Icons.home, 'Logs', TransactionLogPage()),
                  homeMenu(Icons.home, 'Hapi Stores', HapiStoreListPage()),
                  //homeMenu(Icons.home, 'Products', SettingsPage()), // route to product page

                  Divider(),

                  //homeMenu(Icons.settings_sharp, 'Settings', SettingsPage()),
                  homeMenu(
                    Icons.logout_sharp,
                    'Logout',
                    SettingsPage(),
                    isLogout: true,
                  ),
                ],
              ),
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  spacing: 20,
                  children: [
                    Row(
                      spacing: 20,
                      children: [dashboardItem(), dashboardItem()],
                    ),
                    Row(
                      spacing: 20,
                      children: [dashboardItem(), dashboardItem()],
                    ),
                    Row(
                      spacing: 20,
                      children: [dashboardItem(), dashboardItem()],
                    ),
                    Row(
                      spacing: 20,
                      children: [dashboardItem(), dashboardItem()],
                    ),
                  ],
                ),
              ),
            ),
          );
  }

  Future<void> prefetchData() async {
    if (mounted) setState(() => isLoading = true);

    unpaidCreditCount = await dbDelivery.getCountDeliveryWithCreditNotYetPaid();
    pendingDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(
      DeliveryStatus.pending,
    );
    returnedDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(
      DeliveryStatus.returned,
    );
    isDealer = await KVariables.getIsDealer();

    if (mounted) setState(() => isLoading = false);
  }

  void onLogout() {
    KForms.alertDialogConfirm(
      'Logout',
      'Are you sure you want to log out?',
      context,
      () async {
        try {
          setState(() => isLoading = true);
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
            ShowMessage.error(
              context,
              e.message ?? 'There was a problem upon signing out',
            );
          }
          setState(() => isLoading = false);
        }
      },
    );
  }

  ListTile homeMenu(
    IconData icon,
    String title,
    Widget nextPage, {
    int? notifyCount,
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () async {
        Navigator.pop(context); // close the drawer
        if (isLogout) {
          onLogout();
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => nextPage),
          );
          prefetchData();
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
                  child: Text(
                    notifyCount.toString(),
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
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
        child: ClipOval(
          child: Image.asset(
            'assets/images/profile.jpg',
            width: 90,
            height: 90,
            fit: BoxFit.cover,
          ),
        ),
      ),
      decoration: BoxDecoration(
        color: Colors.blue,
        image: DecorationImage(
          image: AssetImage('assets/images/profilebackground.jpg'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget dashboardItem() {
    return Expanded(
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors
              .white, // Note: put color inside BoxDecoration if using decoration
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text("TBA", style: TextStyle(color: Colors.red, fontSize: 18)),
        ),
      ),
    );
  }
}
