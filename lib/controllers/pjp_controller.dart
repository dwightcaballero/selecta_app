import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/tasks.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/pjp_order_decision_service.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/services/scanning_services.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/services/tasks_services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

/// Result container for geolocation check at store site.
class LocationCheckResult {
  final bool passed;
  final String status;
  final String? error;
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool isOutOfRange;

  const LocationCheckResult({
    required this.passed,
    required this.status,
    this.error,
    this.distanceMeters,
    this.accuracyMeters,
    this.isOutOfRange = false,
  });
}

/// Result container for barcode scanning verification.
class ScanningCheckResult {
  final bool passed;
  final String status;
  final List<Scanning> storeScannings;

  const ScanningCheckResult({
    required this.passed,
    required this.status,
    required this.storeScannings,
  });
}

/// Result container for product placement checklist check.
class PlacementCheckResult {
  final bool passed;
  final String status;
  final Placement? storePlacement;

  const PlacementCheckResult({
    required this.passed,
    required this.status,
    this.storePlacement,
  });
}

/// Result container for Book Order checklist check.
class BookOrderCheckResult {
  final bool passed;
  final String status;
  final bool hasBookedOrder;
  final String? noOrderReason;

  const BookOrderCheckResult({
    required this.passed,
    required this.status,
    this.hasBookedOrder = false,
    this.noOrderReason,
  });
}

/// Represents a recommended Selecta product for store ordering.
class StoreRecommendationItem {
  final String productName;
  final String? imageUrl;
  final String category;
  final double sellingPrice;
  final int availableStock;
  final bool isOutOfStock;
  final bool isBestSeller;
  final String? itemImagePath;

  const StoreRecommendationItem({
    required this.productName,
    this.imageUrl,
    this.category = 'Selecta',
    this.sellingPrice = 0.0,
    this.availableStock = 0,
    required this.isOutOfStock,
    this.isBestSeller = true,
    this.itemImagePath,
  });
}

/// Consolidated store ordering recommendations and stock alert result.
class StoreRecommendationsResult {
  final List<StoreRecommendationItem> unplacedRecommendations;
  final List<InventoryItem> outOfStockProducts;

  const StoreRecommendationsResult({
    required this.unplacedRecommendations,
    required this.outOfStockProducts,
  });

  int get unplacedCount => unplacedRecommendations.length;
  int get outOfStockCount => outOfStockProducts.length;
}

/// Compliance and task status indicators for a store on the route.
class StoreComplianceStatus {
  final bool isScanned;
  final bool isBooked;
  final bool isNoOrder;
  final int totalBarcodes;
  final int scannedBarcodes;

  const StoreComplianceStatus({
    this.isScanned = false,
    this.isBooked = false,
    this.isNoOrder = false,
    this.totalBarcodes = 0,
    this.scannedBarcodes = 0,
  });

  bool get hasAnyStatus => isScanned || isBooked || isNoOrder || (totalBarcodes > 0 && scannedBarcodes > 0);
}

/// Result container for Proof of Visit photographic checklist check.
class ProofOfVisitCheckResult {
  final bool passed;
  final String status;
  final ProofOfVisit? proofOfVisit;

  const ProofOfVisitCheckResult({
    required this.passed,
    required this.status,
    this.proofOfVisit,
  });
}

/// Result container for store tasks check.
class TasksCheckResult {
  final bool passed;
  final String status;
  final List<Tasks> pendingTasks;

  const TasksCheckResult({
    required this.passed,
    required this.status,
    required this.pendingTasks,
  });
}

/// Result container for promotional Merch Blitz check.
class MerchBlitzCheckResult {
  final bool passed;
  final String status;

  const MerchBlitzCheckResult({
    required this.passed,
    required this.status,
  });
}

/// Controller responsible for Permanent Journey Plan (PJP) scheduling,
/// store reordering, compliance checklist verification, and visit completion.
class PjpController {
  final HapiStoreService _hapiStoreService;
  final ScanningServices _scanningService;
  final TasksService _tasksService;
  final ConfigurationService _configurationService;
  final DeliveryService _deliveryService;
  final ProofOfVisitService _proofOfVisitService;
  final PjpOrderDecisionService _orderDecisionService;
  final PlacementService _placementService;
  final SelectaProductService _selectaProductService;
  final InventoryService _inventoryService;

  PjpController({
    HapiStoreService? hapiStoreService,
    ScanningServices? scanningService,
    TasksService? tasksService,
    ConfigurationService? configurationService,
    DeliveryService? deliveryService,
    ProofOfVisitService? proofOfVisitService,
    PjpOrderDecisionService? orderDecisionService,
    PlacementService? placementService,
    SelectaProductService? selectaProductService,
    InventoryService? inventoryService,
  })  : _hapiStoreService = hapiStoreService ?? HapiStoreService(),
        _scanningService = scanningService ?? ScanningServices(),
        _tasksService = tasksService ?? TasksService(),
        _configurationService = configurationService ?? ConfigurationService(),
        _deliveryService = deliveryService ?? DeliveryService(),
        _proofOfVisitService = proofOfVisitService ?? ProofOfVisitService(),
        _orderDecisionService = orderDecisionService ?? PjpOrderDecisionService(),
        _placementService = placementService ?? PlacementService(),
        _selectaProductService = selectaProductService ?? SelectaProductService(),
        _inventoryService = inventoryService ?? InventoryService();

  DeliveryService get deliveryService => _deliveryService;

  static const double maxAllowedDistanceMeters = 200.0;

  static const List<String> weekdayNames = [
    PjpScheduleDays.monday,
    PjpScheduleDays.tuesday,
    PjpScheduleDays.wednesday,
    PjpScheduleDays.thursday,
    PjpScheduleDays.friday,
    PjpScheduleDays.saturday,
    PjpScheduleDays.sunday,
  ];

  /// Returns the default PJP day name based on today's weekday.
  String getDefaultDay() {
    return weekdayNames[DateTime.now().weekday - 1];
  }

  /// Checks if the logged-in user is a dealer.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  // ==========================================
  // PJP List & Scheduling (PjpListPage)
  // ==========================================

  /// Stream of store documents scheduled for the specified weekday.
  Stream<QuerySnapshot> getStoresForDayStream(String day) {
    return _hapiStoreService.getListHapiStoresByPjpScheduleAsStream(day);
  }

  /// Stream of all stores (for adding new stores to schedule).
  Stream<QuerySnapshot> getAllStoresStream() {
    return _hapiStoreService.getListHapiStoresAsStream();
  }

  /// Sorts store snapshots by their assigned pjpSequence, placing unsequenced stores
  /// alphabetically at the end.
  List<QueryDocumentSnapshot> sortStoreDocs(List<QueryDocumentSnapshot> docs) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final storeA = a.data() is Hapistore
          ? a.data() as Hapistore
          : Hapistore.fromJson(a.data() as Map<String, Object?>);
      final storeB = b.data() is Hapistore
          ? b.data() as Hapistore
          : Hapistore.fromJson(b.data() as Map<String, Object?>);

      final seqA = storeA.pjpSequence;
      final seqB = storeB.pjpSequence;
      if (seqA != null && seqB != null) return seqA.compareTo(seqB);
      if (seqA != null) return -1;
      if (seqB != null) return 1;
      return storeA.storeName.compareTo(storeB.storeName);
    });
    return sorted;
  }

  /// Filters stores for the "Add Store" picker sheet.
  List<QueryDocumentSnapshot> filterStoresForAddPicker({
    required List<QueryDocumentSnapshot> allDocs,
    required Set<String> excludedStoreIDs,
    required String searchQuery,
  }) {
    final query = searchQuery.trim().toLowerCase();
    return allDocs.where((doc) {
      if (excludedStoreIDs.contains(doc.id)) return false;
      final rawData = doc.data();
      final store = rawData is Hapistore
          ? rawData
          : Hapistore.fromJson(rawData as Map<String, Object?>);
      if (query.isEmpty) return true;
      return store.storeName.toLowerCase().contains(query) ||
          store.storeAddress.toLowerCase().contains(query) ||
          store.storeContact.contains(query);
    }).toList();
  }

  /// Saves the updated PJP sequence order for the selected day, records removed stores,
  /// and writes an audit transaction log.
  Future<void> savePjpSequenceOrder({
    required String selectedDay,
    required List<String> orderedStoreIDs,
    required Set<String> originalStoreIDs,
    required Map<String, Hapistore> storesById,
  }) async {
    final removedStoreIDs = originalStoreIDs.difference(orderedStoreIDs.toSet()).toList();
    await _hapiStoreService.updatePjpSequenceOrder(
      selectedDay,
      orderedStoreIDs,
      removedHapiStoreIDs: removedStoreIDs,
    );

    final storeNames = orderedStoreIDs.map((id) => storesById[id]?.storeName ?? id).join(', ');
    await Helperfunctions.logTransaction(
      'PJP Resequence - $selectedDay',
      'New order: $storeNames',
      LogAction.update,
      page: AppPages.pjpList,
    );
  }

  /// Calculates completed store visits for this week vs total stores on the list.
  ({int completed, int total}) calculatePjpProgress(List<QueryDocumentSnapshot> docs) {
    int completed = 0;
    final now = DateTime.now();
    for (final doc in docs) {
      final raw = doc.data();
      final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
      if (store.lastPjpVisit != null && Helperfunctions.isSameWeek(store.lastPjpVisit!.toDate(), now)) {
        completed++;
      }
    }
    return (completed: completed, total: docs.length);
  }

  // ==========================================
  // PJP Verification Checks (PjpPage)
  // ==========================================

  /// Refreshes the store record from Firestore.
  Future<Hapistore?> refreshStore(String hapiStoreID) async {
    return await _hapiStoreService.getHapiStoreById(hapiStoreID);
  }

  /// Geofence radius in meters for store location verification during visits.
  static const double storeGeofenceRadiusMeters = 200.0;

  /// Verifies store location coordinates and checks whether the device is within 200m range.
  Future<LocationCheckResult> checkLocation(Hapistore store) async {
    if (store.latitude == null || store.longitude == null) {
      return const LocationCheckResult(
        passed: false,
        status: 'No store location saved in database.',
        error: 'Tap "Get Location" below when you are physically at this store.',
        isOutOfRange: false,
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationCheckResult(
          passed: false,
          status: 'Location service (GPS) is turned off.',
          error: 'Please enable GPS on your device to verify store proximity.',
          isOutOfRange: false,
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return const LocationCheckResult(
          passed: false,
          status: 'Location permission denied.',
          error: 'Please grant location permission to verify store proximity.',
          isOutOfRange: false,
        );
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // Fallback to last known position if fresh high-accuracy fix timed out
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return const LocationCheckResult(
          passed: false,
          status: 'Could not acquire GPS position.',
          error: 'Unable to get a GPS fix. Please move to an open area and tap Retry.',
          isOutOfRange: false,
        );
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        store.latitude!,
        store.longitude!,
      );

      final distLabel = distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} km'
          : '${distance.round()} m';

      final accuracyLabel = position.accuracy > 0
          ? '±${position.accuracy.round()}m accuracy'
          : 'high accuracy';

      final bool isWithinRange = distance <= storeGeofenceRadiusMeters;

      if (isWithinRange) {
        return LocationCheckResult(
          passed: true,
          status: 'In range: ~$distLabel away from store ($accuracyLabel)',
          distanceMeters: distance,
          accuracyMeters: position.accuracy,
          isOutOfRange: false,
        );
      } else {
        return LocationCheckResult(
          passed: false,
          status: 'Out of range: ~$distLabel away from store (max allowed: ${storeGeofenceRadiusMeters.round()}m)',
          error: 'You must be within ${storeGeofenceRadiusMeters.round()}m of the store, or tap "Update Location" if the store moved.',
          distanceMeters: distance,
          accuracyMeters: position.accuracy,
          isOutOfRange: true,
        );
      }
    } catch (e) {
      return LocationCheckResult(
        passed: false,
        status: 'Error checking GPS location.',
        error: e.toString().replaceAll('Exception: ', ''),
        isOutOfRange: false,
      );
    }
  }

  /// Obtains current device GPS coordinates with permission checks.
  Future<Position> getCurrentLocation() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is permanently denied. Please allow it in settings.');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Updates store coordinates in Firestore and logs the audit trail.
  Future<Hapistore> updateStoreLocation({
    required String hapiStoreID,
    required Hapistore currentStore,
    required double latitude,
    required double longitude,
  }) async {
    final updatedStore = currentStore.copyWith(
      latitude: latitude,
      longitude: longitude,
    );

    await _hapiStoreService.updateStoreLocation(
      hapiStoreID,
      latitude: latitude,
      longitude: longitude,
    );

    await Helperfunctions.logUpdate(
      currentStore.storeName,
      currentStore.toJson(),
      updatedStore.toJson(),
      page: AppPages.pjp,
    );

    return updatedStore;
  }

  /// Verifies barcode scanning status for the current month.
  Future<ScanningCheckResult> checkScanning(String storeName) async {
    try {
      final scannings = await _scanningService.getScanningsByStoreName(storeName);

      if (scannings.isEmpty) {
        return const ScanningCheckResult(
          passed: false,
          status: 'No barcode assigned to this store.',
          storeScannings: [],
        );
      }

      final now = DateTime.now();
      final activeBarcodes = scannings.where((s) => s.status != ScanningStatus.pullout).toList();

      if (activeBarcodes.isEmpty) {
        return ScanningCheckResult(
          passed: false,
          status: 'All assigned freezers are marked as pullout.',
          storeScannings: scannings,
        );
      }

      final List<Scanning> completedBarcodes = [];
      final List<Scanning> uncompletedBarcodes = [];

      for (final s in activeBarcodes) {
        final isScannedThisMonth = s.status == ScanningStatus.scanned &&
            (s.scannedDate == null ||
                (s.scannedDate!.toDate().year == now.year && s.scannedDate!.toDate().month == now.month));
        final isPending = s.status == ScanningStatus.pending;

        if (isScannedThisMonth || isPending) {
          completedBarcodes.add(s);
        } else {
          uncompletedBarcodes.add(s);
        }
      }

      final bool allPassed = activeBarcodes.isNotEmpty && completedBarcodes.length == activeBarcodes.length;

      final String statusMessage;
      if (allPassed) {
        final pendingCount = completedBarcodes.where((s) => s.status == ScanningStatus.pending).length;
        if (activeBarcodes.length == 1) {
          final s = activeBarcodes.first;
          statusMessage = s.status == ScanningStatus.pending
              ? 'Barcode (${s.barcode}) pending dealer verification.'
              : 'Barcode (${s.barcode}) scanned for ${DateFormat('MMMM yyyy').format(now)}.';
        } else {
          statusMessage = pendingCount > 0
              ? 'All ${activeBarcodes.length} freezer barcodes scanned ($pendingCount pending review).'
              : 'All ${activeBarcodes.length} freezer barcodes scanned for ${DateFormat('MMMM yyyy').format(now)}.';
        }
      } else {
        final notScannedList = uncompletedBarcodes.map((s) => s.barcode).join(', ');
        if (activeBarcodes.length == 1) {
          statusMessage = 'Barcode (${activeBarcodes.first.barcode}) not yet scanned this month.';
        } else {
          statusMessage =
              '${completedBarcodes.length} of ${activeBarcodes.length} freezers scanned. Remaining: [$notScannedList]';
        }
      }

      return ScanningCheckResult(
        passed: allPassed,
        status: statusMessage,
        storeScannings: scannings,
      );
    } catch (e) {
      return const ScanningCheckResult(
        passed: false,
        status: 'Failed to load scanning records',
        storeScannings: [],
      );
    }
  }

  /// Verifies store product placement status.
  Future<PlacementCheckResult> checkPlacement({
    required Hapistore store,
    required bool placementViewed,
  }) async {
    try {
      final placements = await PlacementService.getListOfPlacementsWithinCurrentMonth();
      final matching = placements.where((p) => p.storeName == store.storeName).firstOrNull;

      final now = DateTime.now();
      final lastVisit = store.lastPjpVisit?.toDate();
      final bool lastVisitWithinWeek = lastVisit != null && Helperfunctions.isSameWeek(lastVisit, now);

      final bool isPassed = placementViewed || lastVisitWithinWeek || (matching != null && matching.isFinished);

      String statusMsg;
      if (matching != null && matching.isFinished) {
        statusMsg = 'Placement checklist completed (${matching.progressCount}/12 placed).';
      } else if (matching != null && (placementViewed || matching.progressCount > 0)) {
        statusMsg = 'Placement checklist updated (${matching.progressCount}/12 placed).';
      } else if (placementViewed) {
        statusMsg = 'Placement record viewed and verified.';
      } else if (lastVisitWithinWeek) {
        final dateLabel = DateFormat('EEE, MMM d').format(lastVisit);
        statusMsg = 'Placement verified (PJP visit completed on $dateLabel).';
      } else if (matching != null) {
        statusMsg = 'Placement in progress (${matching.progressCount}/12 placed) — review needed.';
      } else {
        statusMsg = 'Placement checklist not yet reviewed for this store.';
      }

      return PlacementCheckResult(
        passed: isPassed,
        status: statusMsg,
        storePlacement: matching,
      );
    } catch (e) {
      final now = DateTime.now();
      final lastVisit = store.lastPjpVisit?.toDate();
      final bool lastVisitWithinWeek = lastVisit != null && Helperfunctions.isSameWeek(lastVisit, now);

      return PlacementCheckResult(
        passed: placementViewed || lastVisitWithinWeek,
        status: (placementViewed || lastVisitWithinWeek)
            ? 'Placement verified for this week.'
            : 'Failed to load placement records',
      );
    }
  }

  /// Verifies pending and overdue tasks for the store.
  Future<TasksCheckResult> checkTasks(String storeName) async {
    try {
      final tasks = await _tasksService.getTasksByStoreName(storeName);
      final pendingTasks = tasks.where((t) => !t.isTaskDone).toList();

      if (pendingTasks.isEmpty) {
        return TasksCheckResult(
          passed: true,
          status: tasks.isEmpty
              ? 'No pending tasks for this store.'
              : 'All ${tasks.length} task(s) completed.',
          pendingTasks: [],
        );
      } else {
        return TasksCheckResult(
          passed: false,
          status: '${pendingTasks.length} pending / overdue task(s) remaining.',
          pendingTasks: pendingTasks,
        );
      }
    } catch (e) {
      return const TasksCheckResult(
        passed: false,
        status: 'Failed to load store tasks',
        pendingTasks: [],
      );
    }
  }

  /// Verifies promotional Merch Blitz campaign status.
  Future<MerchBlitzCheckResult> checkMerchBlitz(Hapistore store) async {
    try {
      final config = await _configurationService.getConfiguration();
      final startDate = config.merchBlitzStartDate.toDate();
      final endDate = config.merchBlitzEndDate.toDate();

      final now = DateTime.now();
      final s = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
      final e = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

      final isCampaignActive = !now.isBefore(s) && !now.isAfter(e);

      if (!isCampaignActive) {
        return const MerchBlitzCheckResult(
          passed: true,
          status: 'No active Merch Blitz campaign scheduled for today.',
        );
      }

      final status = store.getMerchBlitzStatus(startDate, endDate);
      final bool isSurveyed = status == MerchBlitzStatus.forFinalSurvey || status == MerchBlitzStatus.surveyed;

      String statusMsg;
      if (isSurveyed) {
        final lastDate = store.lastMerchBlitzDate?.toDate();
        final dateStr = lastDate != null ? DateFormat('EEE, MMM d • h:mm a').format(lastDate) : '';
        if (status == MerchBlitzStatus.surveyed) {
          statusMsg = 'Merch Blitz survey completed and verified ($dateStr).';
        } else {
          statusMsg = 'Merch Blitz survey submitted ($dateStr), awaiting dealer final survey.';
        }
      } else {
        statusMsg = 'Store has not yet been surveyed for the Merch Blitz promotion.';
      }

      return MerchBlitzCheckResult(
        passed: isSurveyed,
        status: statusMsg,
      );
    } catch (e) {
      return MerchBlitzCheckResult(
        passed: false,
        status: 'Failed to verify Merch Blitz status: $e',
      );
    }
  }

  /// Verifies whether an order has been booked for the store today or a no-order reason was provided.
  Future<BookOrderCheckResult> checkBookOrder(String storeName) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      bool hasOrderToday = false;
      try {
        final querySnap = await FirebaseFirestore.instance
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.storeName, isEqualTo: storeName)
            .where(DeliveryModelString.createdDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where(DeliveryModelString.createdDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .limit(1)
            .get();
        hasOrderToday = querySnap.docs.isNotEmpty;
      } catch (_) {
        // Fallback in case composite index is not yet built
        try {
          final querySnap = await FirebaseFirestore.instance
              .collection(DELIVERY_COLLECTION_REF)
              .where(DeliveryModelString.storeName, isEqualTo: storeName)
              .limit(10)
              .get();
          for (final doc in querySnap.docs) {
            final data = doc.data();
            final ts = data[DeliveryModelString.createdDate] as Timestamp?;
            if (ts != null) {
              final d = ts.toDate();
              if (d.year == now.year && d.month == now.month && d.day == now.day) {
                hasOrderToday = true;
                break;
              }
            }
          }
        } catch (_) {}
      }

      if (hasOrderToday) {
        return const BookOrderCheckResult(
          passed: true,
          status: 'Order booked for today (Pending Picklist).',
          hasBookedOrder: true,
        );
      }

      // Check if a "no order" decision was recorded for this store today
      final decision = await _orderDecisionService.getTodayNoOrderDecision(storeName);
      if (decision != null) {
        return BookOrderCheckResult(
          passed: true,
          status: 'No order booked today. Reason: ${decision.reason}',
          hasBookedOrder: false,
          noOrderReason: decision.reason,
        );
      }

      return const BookOrderCheckResult(
        passed: false,
        status: 'Order not yet booked and no reason recorded.',
        hasBookedOrder: false,
      );
    } catch (e) {
      return BookOrderCheckResult(
        passed: false,
        status: 'Failed to verify order status: $e',
      );
    }
  }

  /// Records required reason for not booking an order.
  Future<void> recordNoOrderReason({
    required String storeName,
    required String reason,
    required String createdBy,
  }) async {
    await _orderDecisionService.recordNoOrderReason(
      storeName: storeName,
      reason: reason,
      createdBy: createdBy,
    );
    await Helperfunctions.logTransaction(
      'PJP Order Decision - $storeName',
      'No order booked. Reason: $reason',
      LogAction.create,
      page: AppPages.pjp,
    );
  }

  /// Verifies photographic proof of visit for the store.
  Future<ProofOfVisitCheckResult> checkProofOfVisit(String storeName) async {
    try {
      final proof = await _proofOfVisitService.getProofOfVisitForStoreToday(storeName);
      if (proof != null) {
        final visitTime = DateFormat('EEE, MMM d • h:mm a').format(proof.visitDate.toDate());
        return ProofOfVisitCheckResult(
          passed: true,
          status: 'Proof of visit photo verified ($visitTime).',
          proofOfVisit: proof,
        );
      } else {
        return const ProofOfVisitCheckResult(
          passed: false,
          status: 'Proof of visit photo not yet captured.',
        );
      }
    } catch (e) {
      return ProofOfVisitCheckResult(
        passed: false,
        status: 'Failed to verify proof of visit: $e',
      );
    }
  }

  /// Saves a new proof of visit record and logs transaction.
  Future<ProofOfVisit> saveProofOfVisit({
    required String storeName,
    required String imageUrl,
    required String takenBy,
  }) async {
    final record = ProofOfVisit(
      storeName: storeName,
      visitDate: Timestamp.now(),
      imageUrl: imageUrl,
      takenBy: takenBy,
      createdAt: Timestamp.now(),
    );
    final id = await _proofOfVisitService.addProofOfVisit(record);
    await Helperfunctions.logTransaction(
      'Proof of Visit Captured - $storeName',
      'Proof of visit photo saved for visit today',
      LogAction.create,
      page: AppPages.pjp,
    );
    return record.copyWith(id: id);
  }

  /// Marks the store PJP visit as completed and logs an audit transaction.
  Future<void> completeVisit({
    required String hapiStoreID,
    required Hapistore store,
    required String selectedDay,
  }) async {
    await _hapiStoreService.updateLastPjpVisit(hapiStoreID);
    await Helperfunctions.logTransaction(
      'PJP Visit Completed - ${store.storeName}',
      'Completed PJP visit criteria for $selectedDay',
      LogAction.update,
      page: AppPages.pjp,
    );
  }

  /// Fetches a batch map of compliance indicators (scanned this month, order booked today,
  /// or no-order decision logged today) keyed by storeName for the given stores.
  Future<Map<String, StoreComplianceStatus>> getStoreComplianceStatuses(List<String> storeNames) async {
    final Map<String, StoreComplianceStatus> result = {};
    if (storeNames.isEmpty) return result;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final Set<String> scannedStores = {};
    final Set<String> bookedStores = {};
    final Set<String> noOrderStores = {};
    final Map<String, ({int scanned, int total})> storeBarcodeStats = {};

    // Process stores in chunks of 30 due to Firestore 'whereIn' limitation
    for (var i = 0; i < storeNames.length; i += 30) {
      final chunk = storeNames.sublist(i, (i + 30 > storeNames.length) ? storeNames.length : i + 30);

      // 1. Check Scanning (all active barcodes for each store must be scanned or pending)
      final Map<String, List<Map<String, dynamic>>> storeBarcodesMap = {};
      try {
        final scanSnap = await FirebaseFirestore.instance
            .collection(SCANNING_COLLECTION_REF)
            .where('storeName', whereIn: chunk)
            .get();

        for (final doc in scanSnap.docs) {
          final data = doc.data();
          final storeName = (data['storeName'] as String? ?? '').trim().toLowerCase();
          if (storeName.isNotEmpty) {
            storeBarcodesMap.putIfAbsent(storeName, () => []).add(data);
          }
        }
      } catch (_) {}



      for (final sName in chunk) {
        final lower = sName.toLowerCase();
        final barcodes = storeBarcodesMap[lower] ?? [];
        final active = barcodes.where((b) => (b['status'] as String? ?? '').trim() != ScanningStatus.pullout).toList();

        int scannedOrPendingCount = 0;
        for (final b in active) {
          final status = (b['status'] as String? ?? '').trim();
          final scannedDate = b['scannedDate'] as Timestamp?;
          if (status == ScanningStatus.scanned) {
            if (scannedDate != null) {
              final d = scannedDate.toDate();
              if (d.year == now.year && d.month == now.month) {
                scannedOrPendingCount++;
              }
            } else {
              scannedOrPendingCount++;
            }
          } else if (status == ScanningStatus.pending) {
            scannedOrPendingCount++;
          }
        }

        final bool isFullyScanned = active.isNotEmpty && scannedOrPendingCount == active.length;
        if (isFullyScanned) {
          scannedStores.add(lower);
        }
        storeBarcodeStats[lower] = (scanned: scannedOrPendingCount, total: active.length);
      }

      // 2. Check Booked Orders for today in delivery collection
      try {
        final deliverySnap = await FirebaseFirestore.instance
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.storeName, whereIn: chunk)
            .where(DeliveryModelString.createdDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where(DeliveryModelString.createdDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        for (final doc in deliverySnap.docs) {
          final sName = (doc.data()[DeliveryModelString.storeName] as String? ?? '').trim();
          if (sName.isNotEmpty) bookedStores.add(sName.toLowerCase());
        }
      } catch (_) {
        // Fallback without composite index: query by storeName and filter createdDate in-memory
        try {
          final deliverySnap = await FirebaseFirestore.instance
              .collection(DELIVERY_COLLECTION_REF)
              .where(DeliveryModelString.storeName, whereIn: chunk)
              .get();
          for (final doc in deliverySnap.docs) {
            final ts = doc.data()[DeliveryModelString.createdDate] as Timestamp?;
            if (ts != null) {
              final d = ts.toDate();
              if (d.year == now.year && d.month == now.month && d.day == now.day) {
                final sName = (doc.data()[DeliveryModelString.storeName] as String? ?? '').trim();
                if (sName.isNotEmpty) bookedStores.add(sName.toLowerCase());
              }
            }
          }
        } catch (_) {}
      }

      // 3. Check No-Order decisions for today
      try {
        final decisionSnap = await FirebaseFirestore.instance
            .collection(PJP_ORDER_DECISIONS_COLLECTION)
            .where('storeName', whereIn: chunk)
            .where('decision', isEqualTo: 'no_order')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        for (final doc in decisionSnap.docs) {
          final sName = (doc.data()['storeName'] as String? ?? '').trim();
          if (sName.isNotEmpty) noOrderStores.add(sName.toLowerCase());
        }
      } catch (_) {
        try {
          final decisionSnap = await FirebaseFirestore.instance
              .collection(PJP_ORDER_DECISIONS_COLLECTION)
              .where('storeName', whereIn: chunk)
              .where('decision', isEqualTo: 'no_order')
              .get();
          for (final doc in decisionSnap.docs) {
            final ts = doc.data()['date'] as Timestamp?;
            if (ts != null) {
              final d = ts.toDate();
              if (d.year == now.year && d.month == now.month && d.day == now.day) {
                final sName = (doc.data()['storeName'] as String? ?? '').trim();
                if (sName.isNotEmpty) noOrderStores.add(sName.toLowerCase());
              }
            }
          }
        } catch (_) {}
      }
    }

    for (final name in storeNames) {
      final key = name.toLowerCase();
      final stats = storeBarcodeStats[key];
      result[name] = StoreComplianceStatus(
        isScanned: scannedStores.contains(key),
        isBooked: bookedStores.contains(key),
        isNoOrder: noOrderStores.contains(key),
        totalBarcodes: stats?.total ?? 0,
        scannedBarcodes: stats?.scanned ?? 0,
      );
    }

    return result;
  }

  /// Fetches unplaced recommended Selecta products for the store for this month
  /// and all active products currently out of stock today at the depot.
  Future<StoreRecommendationsResult> getStoreRecommendations(String storeName) async {
    try {
      final now = DateTime.now();

      // 1. Placement record for the store in the current month
      final placement = await _placementService.getPlacementByStoreAndDate(storeName, now);
      final placedLowerNames = placement?.placedProductNames
              .map((n) => n.trim().toLowerCase())
              .toSet() ??
          <String>{};

      // Backward compatibility: If placedProductNames is empty, read legacy cotc flags
      if (placedLowerNames.isEmpty && placement != null) {
        final legacyNames = [
          "Watermelon Slice",
          "Chocky Stick",
          "Avocado Choco",
          "Boom Boom Choco",
          "Cornetto Choco",
          "Cornetto Cookies & Dream",
          "Bday 3in1 C-K-U",
          "Bday 3in1 U-M-A",
          "Bday 3+1 C-K-U-M",
          "Sup Double Dutch",
          "Sup Rocky Road",
          "Sup Cookies & Cream",
        ];
        final flags = [
          placement.cotc1,
          placement.cotc2,
          placement.cotc3,
          placement.cotc4,
          placement.cotc5,
          placement.cotc6,
          placement.cotc7,
          placement.cotc8,
          placement.cotc9,
          placement.cotc10,
          placement.cotc11,
          placement.cotc12,
        ];
        for (int i = 0; i < legacyNames.length && i < flags.length; i++) {
          if (flags[i]) {
            placedLowerNames.add(legacyNames[i].trim().toLowerCase());
          }
        }
      }

      // 2. Fetch inventory list
      List<InventoryItem> allInventory = [];
      try {
        allInventory = await _inventoryService
            .getActiveInventoryStream()
            .first
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        final prodDocs = await _selectaProductService.getAllProducts();
        allInventory = prodDocs
            .map((doc) => SelectaProduct.fromSnapshot(doc))
            .where((p) => p.isActive && p.productName.isNotEmpty)
            .map(InventoryItem.fromSelectaProduct)
            .toList();
      }

      final activeInventory = allInventory.where((i) => i.isActive).toList();

      // 3. Out of stock products for today (where availableQuantity <= 0)
      final outOfStockProducts = activeInventory
          .where((i) => i.availableQuantity <= 0 || i.isOutOfStock)
          .toList()
        ..sort((a, b) => Helperfunctions.compareBySrpAndName(
              nameA: a.productName,
              priceA: a.sellingPrice,
              nameB: b.productName,
              priceB: b.sellingPrice,
            ));

      // 4. Target placement products (Best Sellers)
      final bestSellerProducts = await _selectaProductService.getBestSellerProducts();
      final legacyPlacementList = KData.getListPlacement();

      // Map unique lowercased name -> StoreRecommendationItem
      final Map<String, StoreRecommendationItem> targetMap = {};

      if (bestSellerProducts.isNotEmpty) {
        for (final prod in bestSellerProducts) {
          final lowerName = prod.productName.trim().toLowerCase();
          final matchingInv = activeInventory.where(
            (i) => i.productName.trim().toLowerCase() == lowerName,
          ).firstOrNull;

          targetMap[lowerName] = StoreRecommendationItem(
            productName: prod.productName,
            imageUrl: matchingInv?.imageUrl ?? prod.imageUrl,
            category: matchingInv?.category ?? prod.category,
            sellingPrice: matchingInv?.sellingPrice ?? prod.sellingPrice,
            availableStock: matchingInv?.availableQuantity ?? 0,
            isOutOfStock: matchingInv != null ? (matchingInv.availableQuantity <= 0 || matchingInv.isOutOfStock) : true,
            isBestSeller: true,
          );
        }
      }

      // Include any active InventoryItems tagged as best seller
      for (final item in activeInventory) {
        if (ProductTag.isBestSeller(item.tag)) {
          final lowerName = item.productName.trim().toLowerCase();
          if (!targetMap.containsKey(lowerName)) {
            targetMap[lowerName] = StoreRecommendationItem(
              productName: item.productName,
              imageUrl: item.imageUrl,
              category: item.category.isNotEmpty ? item.category : 'Selecta',
              sellingPrice: item.sellingPrice,
              availableStock: item.availableQuantity,
              isOutOfStock: item.availableQuantity <= 0 || item.isOutOfStock,
              isBestSeller: true,
            );
          }
        }
      }

      // Fallback to legacy placement list if no best sellers found
      if (targetMap.isEmpty) {
        for (final legacy in legacyPlacementList) {
          final lowerName = legacy.itemName.trim().toLowerCase();
          final matchingInv = activeInventory.where(
            (i) => i.productName.trim().toLowerCase() == lowerName,
          ).firstOrNull;

          targetMap[lowerName] = StoreRecommendationItem(
            productName: legacy.itemName,
            imageUrl: matchingInv?.imageUrl,
            category: matchingInv?.category ?? 'Selecta',
            sellingPrice: matchingInv?.sellingPrice ?? 0.0,
            availableStock: matchingInv?.availableQuantity ?? 0,
            isOutOfStock: matchingInv != null ? (matchingInv.availableQuantity <= 0 || matchingInv.isOutOfStock) : true,
            isBestSeller: true,
            itemImagePath: legacy.itemImagePath,
          );
        }
      }

      // 5. Filter for unplaced items
      final unplacedRecommendations = targetMap.entries
          .where((entry) => !placedLowerNames.contains(entry.key))
          .map((entry) => entry.value)
          .toList()
        ..sort((a, b) => Helperfunctions.compareBySrpAndName(
              nameA: a.productName,
              priceA: a.sellingPrice,
              nameB: b.productName,
              priceB: b.sellingPrice,
            ));

      return StoreRecommendationsResult(
        unplacedRecommendations: unplacedRecommendations,
        outOfStockProducts: outOfStockProducts,
      );
    } catch (e) {
      return const StoreRecommendationsResult(
        unplacedRecommendations: [],
        outOfStockProducts: [],
      );
    }
  }
}
