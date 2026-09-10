import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardController {
  static Future<DashboardDTO> getLatestDashboardData() async {
    // Initialize Components
    var dashboardDTO = DashboardDTO.empty();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    DeliveryService dbDelivery = DeliveryService();

    // SAVE: last sync date and time
    await prefs.setString('last_sync_time', DateTime.now().toIso8601String());

    // DASHBOARD: notifications
    dashboardDTO.unpaidCreditCount = await dbDelivery.getCountDeliveryWithCreditNotYetPaid() ?? 0;
    dashboardDTO.pendingDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(DeliveryStatus.pending) ?? 0;
    dashboardDTO.returnedDeliveryCount = await dbDelivery.getCountDeliveriesByStatus(DeliveryStatus.returned) ?? 0;

    // DASHBOARD: buying and non Buying
    var listStores = await HapiStoreService().getListHapiStores();
    var listDelivery = await DeliveryService().getListDeliveryWithinCurrentMonth();
    double totalBuyingSales = 0;

    // For each store, check if there are delivered transactions in order to determine if they are buying or not
    for (var store in listStores) {
      var listTransactions = listDelivery.where((delivery) => delivery.storeName.toLowerCase() == store.storeName.toLowerCase());

      // If there are delivered transactions, compute the total delivered amount of all transactions for thruput computation
      if (listTransactions.isNotEmpty) {
        for (var delivery in listTransactions) {
          totalBuyingSales += delivery.cashAmount + delivery.onlineAmount + delivery.creditAmount;
        }

        dashboardDTO.buyingCount += 1;
      } else {
        dashboardDTO.nonBuyingCount += 1;
      }
    }

    // DASHBOARD: thruput of buying stores
    dashboardDTO.buyingThruput = totalBuyingSales / dashboardDTO.buyingCount;

    // SAVE: dashboard data
    String jsonString = jsonEncode(dashboardDTO.toJson());
    await prefs.setString('dashboard_DTO', jsonString);

    return dashboardDTO;
  }

  static Future<bool> isLastSyncToday() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dateString = prefs.getString('last_sync_time');

    if (dateString == null) return false;
    DateTime lastSync = DateTime.parse(dateString);
    return DateUtils.isSameDay(lastSync, DateTime.now());
  }

  static Future<String> getLastSync() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dateString = prefs.getString('last_sync_time');

    if (dateString == null) return 'Never';
    DateTime lastSync = DateTime.parse(dateString);
    return DateFormat('MM/dd/yyyy, hh:mm a').format(lastSync);
  }
}
