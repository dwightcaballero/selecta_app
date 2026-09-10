import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/kpi_controller.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/kpi_dto.dart';
import 'package:flutter_app/views/pages/transactionlist_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';

class BuyinglistPage extends StatefulWidget {
  const BuyinglistPage({super.key});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  // List of screens to navigate
  List<Widget> get _screens => [
    _screenList(listBuying, Icon(Icons.check, color: Colors.green, size: 40)),
    _screenList(listNonBuying, Icon(Icons.close, color: Colors.red, size: 40)),
  ];
  int _currentIndex = 0;
  List<KPIBuying> listBuying = [];
  List<KPIBuying> listNonBuying = [];
  String appbarTitle = '';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar(appbarTitle),
      body: isLoading ? KForms.loadingScreen() : Padding(padding: const EdgeInsets.all(20.0), child: _screens[_currentIndex]),

      // 4. Implement the NavigationBar
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          _currentIndex = index; // Rebuilds the UI with the new screen
          if (_currentIndex == 0) {
            appbarTitle = 'KPI - Buying (${listBuying.length})';
          } else {
            appbarTitle = 'KPI - Non Buying (${listNonBuying.length})';
          }
          setState(() {});
        },
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Buying Stores'),
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Non Buying Stores'),
        ],
      ),
    );
  }

  void prefetchData() async {
    setState(() => isLoading = true);

    // Get list of buying and non buying stores
    List<KPIBuying> buying = [];
    List<KPIBuying> nonBuying = [];
    (buying, nonBuying) = await KPIController.getListOfBuyingAndNonBuyingStores();
    listBuying = buying;
    listNonBuying = nonBuying;
    appbarTitle = 'KPI - Buying (${listBuying.length})';

    setState(() => isLoading = false);
  }

  Widget _screenList(List<KPIBuying> listStore, Icon icon) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: ListView.builder(
        padding: EdgeInsets.only(bottom: 80),
        itemCount: listStore.length,
        itemBuilder: (context, index) {
          KPIBuying store = listStore[index];
          return InkWell(
            onTap: () => Helperfunctions.navigateTo(context, TransactionListPage(storeName: store.storeName)),
            child: ContainerWidget(
              title: store.storeName,
              description1: 'Order Count: ${store.orderCount}',
              description2: 'Order Total: ${Helperfunctions.formatDoubleAmountForDisplay(store.deliveredAmount)}',
              icon: icon,
            ),
          );
        },
      ),
    );
  }
}
