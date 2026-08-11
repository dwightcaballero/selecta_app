import 'package:flutter/material.dart';
import 'package:flutter_app/data/notifiers.dart';

class NavbarWidget extends StatelessWidget {
  const NavbarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selectedPageNotifier,
      builder: (BuildContext context, int selectedPage, Widget? child) {
        return NavigationBar(
          destinations: [
            NavigationDestination(icon: Icon(Icons.receipt), label: "Deliveries"),
            NavigationDestination(icon: Icon(Icons.local_convenience_store_outlined), label: "Hapi Stores"),
          ],
          onDestinationSelected: (int value){
            selectedPageNotifier.value = value;
          },
          selectedIndex: selectedPage,
        );
      },
    );
  }
}