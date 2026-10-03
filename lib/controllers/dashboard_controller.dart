import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
import 'package:selecta_ops/services/scanning_services.dart';
import 'package:selecta_ops/services/tasks_services.dart';
import 'package:selecta_ops/services/user_services.dart';
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
  final ScanningServices _scanningService = ScanningServices();

  /// Live count stream for pending and overdue tasks.
  Stream<int> getTasksPendingAndOverdueCountStream() => _tasksService.getPendingAndOverdueCountStream();

  /// Live count stream for unsurveyed merch blitz stores.
  Stream<int> getMerchBlitzCountStream({bool forDealer = false}) => _hapiStoreService.getUnsurveyedMerchBlitzCountStream(forDealer: forDealer);

  /// Live count stream for purchase orders awaiting invoice upload.
  Stream<int> getPurchaseOrdersAwaitingCountStream() => _purchaseOrderService.getAwaitingInvoiceCountStream();

  /// Live count stream for orders currently awaiting picklist completion for [date] (defaults to current day).
  Stream<int> getPendingPicklistsCountStream({DateTime? date}) => _deliveryService.getPendingPicklistCountStream(date: date);

  /// Live count stream for deliveries pending completion for [date] (defaults to current day).
  Stream<int> getPendingDeliveriesCountStream({DateTime? date}) => _deliveryService.getPendingDeliveriesCountStream(date: date);

  /// Live count stream for stores in PJP of current day that are not yet visited.
  Stream<int> getPendingPjpCountStream({DateTime? date}) => _hapiStoreService.getPendingPjpCountStream(date);

  /// Live count stream for pending scannings (not scanned + unassigned).
  Stream<int> getPendingScanningCountStream() {
    return _scanningService.getScanningsStream().asyncMap((scannings) async {
      final listStores = await HapiStoreService.getListHapiStores();
      final filteredScannings = scannings.where((s) => s.status != ScanningStatus.pullout).toList();
      final notScannedCount = filteredScannings
          .where((s) => s.status == ScanningStatus.notScanned || s.status == ScanningStatus.pending)
          .length;

      final assignedStoreNames = <String>{};
      for (final s in filteredScannings) {
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
      unassignedCount += filteredScannings.where((s) => s.status == ScanningStatus.unassigned).length;

      return notScannedCount + unassignedCount;
    });
  }

  /// Fetches the currently logged in user profile from storage.
  Future<Users?> getCurrentUser() => KVariables.getUser();

  /// Checks if the current logged-in user is a Dealer.
  Future<bool> isCurrentUserDealer() => KVariables.getIsDealer();

  static Future<DashboardDTO>? _activeSyncFuture;

  /// Cooldown window during which automatic/background sync requests are skipped.
  static const Duration syncCooldown = Duration(minutes: 5);

  /// Retrieves cached [DashboardDTO] from SharedPreferences if available.
  Future<DashboardDTO?> getCachedDashboardData() => getCachedDashboardDataStatic();

  /// Static helper to retrieve cached [DashboardDTO] from SharedPreferences if available.
  static Future<DashboardDTO?> getCachedDashboardDataStatic() async {
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

  /// Retrieves the raw [DateTime] of the last successful sync from SharedPreferences.
  static Future<DateTime?> getLastSyncDateTime() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? dateString = prefs.getString('last_sync_time');
    if (dateString == null) return null;
    return DateTime.tryParse(dateString);
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
  Future<void> saveDashboardData(DashboardDTO dashboardDTO, [String? lastSyncDateTime]) => saveDashboardDataStatic(dashboardDTO, lastSyncDateTime);

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
  ///
  /// - When [force] is `false` (default for automatic/navigation triggers), the sync is
  ///   skipped if the last sync was within [syncCooldown] (5 minutes) and cached data exists.
  /// - Only one sync runs at a time: concurrent callers reuse the in-flight sync Future.
  static Future<DashboardDTO> getLatestDashboardData({bool force = false}) async {
    // 1. Reuse running in-flight sync if one is currently active
    if (_activeSyncFuture != null) {
      return _activeSyncFuture!;
    }

    // 2. Enforce 5-minute cooldown for automatic syncs
    if (!force) {
      final lastSync = await getLastSyncDateTime();
      if (lastSync != null && DateTime.now().difference(lastSync) < syncCooldown) {
        final cached = await getCachedDashboardDataStatic();
        if (cached != null) {
          return cached;
        }
      }
    }

    // 3. Initiate and track execution
    final syncFuture = _fetchLatestDashboardDataFromNetwork();
    _activeSyncFuture = syncFuture;

    try {
      return await syncFuture;
    } finally {
      _activeSyncFuture = null;
    }
  }

  static Future<DashboardDTO> _fetchLatestDashboardDataFromNetwork() async {
    // Initialize Components
    var dashboardDTO = DashboardDTO.empty();

    // DASHBOARD: notifications
    dashboardDTO.unpaidCreditCount = await DeliveryService.getCountDeliveryWithCreditNotYetPaid() ?? 0;
    dashboardDTO.pendingPicklistCount = await DeliveryService.getCountPendingPicklistsForDate(DateTime.now());
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
    dashboardDTO.buyingThruput = dashboardDTO.buyingCount == 0 ? 0.0 : dashboardDTO.totalBuyingSales / dashboardDTO.buyingCount;

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
