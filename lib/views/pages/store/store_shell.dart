import 'package:flutter/material.dart';
import 'package:selecta_ops/views/pages/store/store_account_page.dart';
import 'package:selecta_ops/views/pages/store/store_catalog_page.dart';
import 'package:selecta_ops/views/pages/store/store_home_page.dart';
import 'package:selecta_ops/views/pages/store/store_orders_page.dart';

/// Root navigation shell for Hapi Store portal.
/// Displays a 4-tab bottom navigation bar for Home, Catalog, Orders, and Account.
class StoreShell extends StatefulWidget {
  final int initialIndex;

  const StoreShell({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      StoreHomePage(onNavigateToTab: _onTabSelected),
      const StoreCatalogPage(),
      const StoreOrdersPage(),
      const StoreAccountPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.icecream_outlined),
            selectedIcon: Icon(Icons.icecream_rounded),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
