import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';

class BuyinglistPage extends StatefulWidget {
  const BuyinglistPage({super.key});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  // 1. Track the active index
  int _currentIndex = 0;

  // 2. Define the list of screens to navigate between
  late final List<Widget> _screens = [_listBuying(), _listNonBuying()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('KPI - Buying'),
      body: _screens[_currentIndex],

      // 4. Implement the NavigationBar
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index; // Rebuilds the UI with the new screen
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Buying Stores'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Non buying Stores'),
        ],
      ),
    );
  }

  Widget _listBuying() {
    return Center(child: Text('Buying Stores', style: TextStyle(fontSize: 24)));
  }

  Widget _listNonBuying() {
    return Center(child: Text('Non Buying Stores', style: TextStyle(fontSize: 24)));
  }

  // Widget _storeListView() {
  //   return SizedBox(
  //     height: MediaQuery.sizeOf(context).height * 0.80,
  //     width: MediaQuery.sizeOf(context).width,

  //     child: StreamBuilder(
  //       stream: db.getListHapiStoreSearch(_searchQuery),
  //       builder: (BuildContext context, AsyncSnapshot snapshot) {
  //         if (snapshot.hasError) {
  //           return const Center(child: Text('Something went wrong'));
  //         }
  //         if (snapshot.connectionState == ConnectionState.waiting) {
  //           return const Center(child: Text("Loading..."));
  //         }
  //         if (snapshot.data!.docs.isEmpty) {
  //           return const Center(child: Text("No results found"));
  //         }

  //         List listHapiStore = snapshot.data?.docs;

  //         return ListView.builder(
  //           padding: EdgeInsets.only(bottom: 80),
  //           itemCount: listHapiStore.length,
  //           itemBuilder: (context, index) {
  //             Hapistore hapistore = listHapiStore[index].data();
  //             String hapistoreID = listHapiStore[index].id;

  //             return InkWell(
  //               onTap: () {
  //                 _isDealer
  //                     ? Navigator.push(
  //                         context,
  //                         MaterialPageRoute(
  //                           builder: (context) {
  //                             return HapiStorePage(hapiStoreID: hapistoreID, hapistore: hapistore);
  //                           },
  //                         ),
  //                       )
  //                     : null;
  //               },
  //               child: ContainerWidget(title: hapistore.storeName, description1: hapistore.storeContact, description2: hapistore.storeAddress),
  //             );
  //           },
  //         );
  //       },
  //     ),
  //   );
  // }
}
