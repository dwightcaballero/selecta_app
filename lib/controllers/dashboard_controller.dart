import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/dashboard_dto.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/services/scanning_services.dart';
import 'package:flutter_app/services/tasks_services.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller coordinating main dashboard and salesman dashboard business logic,
/// role management, live count streams, syncing, and caching.
class DashboardController {
  final TasksService _tasksService = TasksService();
  final HapiStoreService _hapiStoreService = HapiStoreService();
  final PurchaseOrderService _purchaseOrderService = PurchaseOrderService();
  final DeliveryService _deliveryService = DeliveryService();
  final UserService _userService = UserService();

  /// Live count stream for pending and overdue tasks.
  Stream<int> getTasksPendingAndOverdueCountStream() =>
      _tasksService.getPendingAndOverdueCountStream();

  /// Live count stream for unsurveyed merch blitz stores.
  Stream<int> getMerchBlitzCountStream({bool forDealer = false}) =>
      _hapiStoreService.getUnsurveyedMerchBlitzCountStream(forDealer: forDealer);

  /// Live count stream for purchase orders awaiting invoice upload.
  Stream<int> getPurchaseOrdersAwaitingCountStream() =>
      _purchaseOrderService.getAwaitingInvoiceCountStream();

  /// Live count stream for orders currently awaiting picklist completion.
  Stream<int> getPendingPicklistsCountStream() =>
      _deliveryService.getPendingPicklistCountStream();

  /// Fetches the currently logged in user profile from storage.
  Future<Users?> getCurrentUser() => KVariables.getUser();

  /// Checks if the current logged-in user is a Dealer.
  Future<bool> isCurrentUserDealer() => KVariables.getIsDealer();

  /// Retrieves cached [DashboardDTO] from SharedPreferences if available.
  Future<DashboardDTO?> getCachedDashboardData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('dashboard_DTO');
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return DashboardDTO.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Switches the business role between Dealer and Salesman, updating Firestore and local cache.
  Future<String> switchUserRole(bool isCurrentlyDealer) async {
    final newRole = isCurrentlyDealer ? BusinessRole.salesman : BusinessRole.dealer;

    // 1. Update Firebase Firestore
    final currentEmail = FirebaseAuth.instance.currentUser?.email;
    if (currentEmail != null && currentEmail.isNotEmpty) {
      await _userService.updateUserRoleByEmail(currentEmail, newRole);
    }

    // 2. Update SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final currentUser = await KVariables.getUser();
    if (currentUser != null) {
      final updatedUser = currentUser.copyWith(role: newRole);
      await prefs.setString('user_data', jsonEncode(updatedUser.toJson()));
    }
    await prefs.setString(SharedPrefKeys.role, newRole);

    HapiStoreService.invalidateCache();
    return newRole;
  }

  /// Signs out the current user via auth service.
  Future<void> signOut() async {
    await authService.value.signOut();
  }

  /// Saves [DashboardDTO] and sync timestamp to SharedPreferences.
  Future<void> saveDashboardData(DashboardDTO dashboardDTO, [String? lastSyncDateTime]) =>
      saveDashboardDataStatic(dashboardDTO, lastSyncDateTime);

  /// Static helper to save [DashboardDTO] and sync timestamp to SharedPreferences.
  static Future<void> saveDashboardDataStatic(DashboardDTO dashboardDTO, [String? lastSyncDateTime]) async {
    final prefs = await SharedPreferences.getInstance();
    DateTime syncTime = DateTime.now();
    if (lastSyncDateTime != null && lastSyncDateTime.isNotEmpty) {
      final parsed = DateTime.tryParse(lastSyncDateTime);
      if (parsed != null) {
        syncTime = parsed;
      }
    }
    await prefs.setString('last_sync_time', syncTime.toIso8601String());
    final jsonString = jsonEncode(dashboardDTO.toJson());
    await prefs.setString('dashboard_DTO', jsonString);
  }

  /// Computes and caches fresh dashboard statistics across all operational domains.
  static Future<DashboardDTO> getLatestDashboardData() async {
    // Initialize Components
    var dashboardDTO = DashboardDTO.empty();

    // DASHBOARD: notifications
    dashboardDTO.unpaidCreditCount = await DeliveryService.getCountDeliveryWithCreditNotYetPaid() ?? 0;
    dashboardDTO.pendingPicklistCount = await DeliveryService.getCountDeliveriesByStatus(DeliveryStatus.pendingPicklist) ?? 0;
    dashboardDTO.pendingDeliveryCount = await DeliveryService.getCountDeliveriesByStatus(DeliveryStatus.pending) ?? 0;
    dashboardDTO.returnedDeliveryCount = await DeliveryService.getCountDeliveriesByStatus(DeliveryStatus.returned) ?? 0;
    dashboardDTO.overpaymentCount = await PurchaseOrderService.getCountDeliveriesNotYetSettled() ?? 0;

    // DASHBOARD: buying and non Buying
    var listStores = await HapiStoreService.getListHapiStores();
    var listDelivery = await DeliveryService.getListDeliveryWithinCurrentMonth();

    // DASHBOARD: PJP pending visit count for today
    dashboardDTO.pendingPjpCount = HapiStoreService.countPendingPjpVisitsForToday(listStores);

    // For each store, check if there are delivered transactions in order to determine if they are buying or not
    for (var store in listStores) {
      var listTransactions = listDelivery.where((delivery) => delivery.storeName.toLowerCase() == store.storeName.toLowerCase());

      // If there are delivered transactions, compute the total delivered amount of all transactions for thruput computation
      if (listTransactions.isNotEmpty) {
        for (var delivery in listTransactions) {
          dashboardDTO.totalBuyingSales += delivery.cashAmount + delivery.onlineAmount + delivery.creditAmount;
        }

        dashboardDTO.buyingCount += 1;
        dashboardDTO.totaltransactionCount += listTransactions.length;
      } else {
        dashboardDTO.nonBuyingCount += 1;
      }
    }
    dashboardDTO.totalHapiStores = listStores.length;

    // DASHBOARD: thruput of buying stores
    dashboardDTO.buyingThruput = dashboardDTO.buyingCount == 0
        ? 0.0
        : dashboardDTO.totalBuyingSales / dashboardDTO.buyingCount;

    // DASHBOARD: total invoice amount for the current month
    dashboardDTO.totalInvoiceAmount = await PurchaseOrderService.getTotalInvoiceAmountForCurrentMonth();

    // DASHBOARD: total stores with finished placement
    dashboardDTO.totalPlacementCount = await PlacementService.getCountOfFinishedPlacements();

    // DASHBOARD: total stores opened this month
    dashboardDTO.totalExpansionCount = (await HapiStoreService.getListHapiStoresWithOpeningDateInCurrentMonth()).length;

    // DASHBOARD: total scanned, not scanned (including pending), and unassigned stores
    var listScannings = await ScanningServices.getAllScannings();
    listScannings = listScannings.where((scanning) => scanning.status != ScanningStatus.pullout).toList();
    dashboardDTO.totalScanCount = listScannings.where((scanning) => scanning.status == ScanningStatus.scanned).length;
    dashboardDTO.totalNotScannedCount = listScannings
        .where((scanning) => scanning.status == ScanningStatus.notScanned || scanning.status == ScanningStatus.pending)
        .length;

    final assignedStoreNames = <String>{};
    for (final s in listScannings) {
      if (s.barcode.trim().isNotEmpty && s.storeName.trim().isNotEmpty) {
        assignedStoreNames.add(s.storeName.trim().toLowerCase());
      }
    }

    int unassignedCount = 0;
    for (final store in listStores) {
      final name = store.storeName.trim();
      if (name.isEmpty) continue;
      if (!assignedStoreNames.contains(name.toLowerCase())) {
        unassignedCount++;
      }
    }
    unassignedCount += listScannings.where((s) => s.status == ScanningStatus.unassigned).length;
    dashboardDTO.totalUnassignedCount = unassignedCount;

    // SAVE: dashboard data and sync timestamp
    await saveDashboardDataStatic(dashboardDTO);

    return dashboardDTO;
  }

  /// Checks if the last sync was performed today.
  static Future<bool> isLastSyncToday() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dateString = prefs.getString('last_sync_time');

    if (dateString == null) return false;
    try {
      DateTime lastSync = DateTime.parse(dateString);
      return DateUtils.isSameDay(lastSync, DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Returns a formatted string representing the last sync timestamp.
  static Future<String> getLastSync() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dateString = prefs.getString('last_sync_time');

    if (dateString == null) return 'Never';
    DateTime lastSync = DateTime.parse(dateString);
    return DateFormat('MM/dd/yyyy, hh:mm a').format(lastSync);
  }
}
