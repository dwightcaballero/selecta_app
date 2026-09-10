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
  final List<Widget> _screens = [
    const Center(child: Text('Home Screen', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Search Screen', style: TextStyle(fontSize: 24))),
    const Center(child: Text('Profile Screen', style: TextStyle(fontSize: 24))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Buying'),
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
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
