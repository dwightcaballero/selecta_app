import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/notifiers.dart';
import 'package:flutter_app/views/pages/endofday_page.dart';
import 'package:flutter_app/views/pages/hapistorelist_page.dart';
import 'package:flutter_app/views/pages/deliverylist_page.dart';
import 'package:flutter_app/views/widgets/navbar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Widget> pages = [
  DeliveryListPage(),
  HapiStoreListPage()
];

class WidgetTree extends StatelessWidget {
  const WidgetTree({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          actions: [
            IconButton(
              onPressed: () async {
                isDarkModeNotifier.value = !isDarkModeNotifier.value;
                final SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool(KConstants.themeModeKey, isDarkModeNotifier.value);
              }, 
              icon: ValueListenableBuilder(
                valueListenable:  isDarkModeNotifier,
                builder: (BuildContext context, bool isDarkMode, Widget? child) {
                  return isDarkMode
                  ? Icon(Icons.light_mode)
                  : Icon(Icons.dark_mode);
                },
              ),
            ),
            IconButton(
              onPressed: () {
                // Navigator.pushReplacement //! push a new MAIN page w/o back button (ex. login page)
                Navigator.push(context, MaterialPageRoute(builder: (context) { //! next page w/ back button
                  return EndofdayPage();
                },));
              },
              icon: Icon(Icons.settings),
            ),
          ],
        ),
        body: ValueListenableBuilder(
          valueListenable:  selectedPageNotifier,
          builder: (BuildContext context, int selectedPage, Widget? child) {
            return pages.elementAt(selectedPage);
          },
        ),
        
        bottomNavigationBar: NavbarWidget(),
    );
  }
}