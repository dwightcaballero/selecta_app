import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';

Widget hapistoreDropdown(
  TextEditingController dropdownHapiStore, {
  VoidCallback? onChanged,
}) {
  final HapiStoreService dbHS = HapiStoreService();
  return StreamBuilder(
    stream: dbHS.getListHapiStores(),
    builder: (BuildContext context, AsyncSnapshot snapshot) {
      final listHapiStore = snapshot.data?.docs ?? [];
      List<DropdownMenuEntry<String>> listDropdownItems = [];
      for (int i = 0; i < listHapiStore.length; i++) {
        Hapistore hapistore = listHapiStore[i].data();
        listDropdownItems.add(
          DropdownMenuEntry(
            value: hapistore.storeName,
            label: hapistore.storeName,
          ),
        );
      }

      return KForms.dropdown(
        'Hapi Store',
        listDropdownItems,
        dropdownHapiStore,
        onSelected: onChanged,
      );
    },
  );
}
