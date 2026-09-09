import 'dart:convert';

import 'package:flutter_app/dto/buying_dto.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeService {
  // For each store, check if there are any deliveries within the current month. If there are, add it to the list of buying stores.
  Future<List<BuyingDto>> getListOfBuyingAndNonBuyingStores() async {
    List<BuyingDto> listBuyingStores = [];

    var listStores = await HapiStoreService().getListHapiStores();
    var listDelivery = await DeliveryService().getListDeliveryWithinCurrentMonth();

    for (var store in listStores) {
      var listTransactions = listDelivery.where(
        (delivery) => delivery.storeName.toLowerCase() == store.storeName.toLowerCase(),
      );

      if (listTransactions.isNotEmpty) {
        // Get the total delivered amount of all transactions
        double deliveredAmount = 0;
        for (var delivery in listTransactions) {
          deliveredAmount += delivery.cashAmount + delivery.onlineAmount + delivery.creditAmount;
        }

        listBuyingStores.add(
          BuyingDto(
            storeName: store.storeName,
            isBuying: true,
            buyingCount: listTransactions.length,
            listDeliveries: listTransactions.toList(),
            deliveredAmount: deliveredAmount,
          ),
        );
      } else {
        listBuyingStores.add(
          BuyingDto(
            storeName: store.storeName,
            isBuying: false,
            buyingCount: 0,
            listDeliveries: [],
            deliveredAmount: 0,
          ),
        );
      }
    }

    return listBuyingStores;
  }

  Future<void> saveLastSyncDateTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_time', DateFormat('dd/MM/yyyy hh:mma').format(DateTime.now()));
  }

  static Future<String> getLastSyncDateTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Read the JSON string
    String? jsonString = prefs.getString('last_sync_time');

    if (jsonString == null) {
      return 'Last Sync: Never'; // No data saved yet
    }

    return jsonString;
  }

  Future<DashboardDto?> getDataFromSharedPrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('dashboard_DTO');

    if (jsonString != null) {
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return DashboardDto(
        buyingCount: jsonMap['buyingCount'] ?? 0,
        nonBuyingCount: jsonMap['nonBuyingCount'] ?? 0,
        buyingThruput: jsonMap['buyingThruput'] ?? 0,
      );
    }

    return null;
  }

  Future<void> saveDataToSharedPrefs(DashboardDto record) async {
    // save the user data in shared preferences cache
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Convert object to Map, then to JSON String
    String jsonString = jsonEncode(record.toJson());

    // 2. Save the string using a unique key
    await prefs.setString('dashboard_DTO', jsonString);
  }
}
