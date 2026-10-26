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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2430) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF2E3644) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              offset: const Offset(0, -2),
              blurRadius: 8,
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: theme.colorScheme.primary),
              label: 'Home',
            ),
            NavigationDestination(
              icon: const Icon(Icons.icecream_outlined),
              selectedIcon: Icon(Icons.icecream_rounded, color: theme.colorScheme.primary),
              label: 'Catalog',
            ),
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: theme.colorScheme.primary),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: const Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded, color: theme.colorScheme.primary),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
