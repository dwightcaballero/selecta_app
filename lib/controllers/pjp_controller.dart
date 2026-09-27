import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/services/configuration_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/services/scanning_services.dart';
import 'package:flutter_app/services/tasks_services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

/// Result container for geolocation check at store site.
class LocationCheckResult {
  final bool passed;
  final String status;
  final String? error;

  const LocationCheckResult({
    required this.passed,
    required this.status,
    this.error,
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

  PjpController({
    HapiStoreService? hapiStoreService,
    ScanningServices? scanningService,
    TasksService? tasksService,
    ConfigurationService? configurationService,
  })  : _hapiStoreService = hapiStoreService ?? HapiStoreService(),
        _scanningService = scanningService ?? ScanningServices(),
        _tasksService = tasksService ?? TasksService(),
        _configurationService = configurationService ?? ConfigurationService();

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

  /// Verifies current device GPS location against store coordinates.
  Future<LocationCheckResult> checkLocation(Hapistore store) async {
    if (store.latitude == null || store.longitude == null) {
      return const LocationCheckResult(
        passed: false,
        status: 'No store location saved in database.',
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationCheckResult(
          passed: false,
          status: 'GPS services disabled',
          error: 'GPS is turned off. Please enable device location services.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationCheckResult(
            passed: false,
            status: 'Location permission denied',
            error: 'Location permission denied.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationCheckResult(
          passed: false,
          status: 'Permission permanently denied',
          error: 'Location permission permanently denied. Enable in device settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        store.latitude!,
        store.longitude!,
      );

      if (distance <= maxAllowedDistanceMeters) {
        return LocationCheckResult(
          passed: true,
          status: 'Within range (${distance.toStringAsFixed(0)}m away, max ${maxAllowedDistanceMeters.toStringAsFixed(0)}m)',
        );
      } else {
        final distLabel = distance >= 1000
            ? '${(distance / 1000).toStringAsFixed(1)}km'
            : '${distance.toStringAsFixed(0)}m';
        return LocationCheckResult(
          passed: false,
          status: 'Out of range ($distLabel away, max ${maxAllowedDistanceMeters.toStringAsFixed(0)}m)',
        );
      }
    } catch (e) {
      return LocationCheckResult(
        passed: false,
        status: 'Unable to acquire location',
        error: 'Failed to get GPS location: $e',
      );
    }
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
      Scanning? scannedThisMonth;

      for (final s in scannings) {
        if (s.status == ScanningStatus.scanned) {
          if (s.scannedDate != null) {
            final date = s.scannedDate!.toDate();
            if (date.year == now.year && date.month == now.month) {
              scannedThisMonth = s;
              break;
            }
          } else {
            scannedThisMonth = s;
            break;
          }
        }
      }

      if (scannedThisMonth != null) {
        return ScanningCheckResult(
          passed: true,
          status: 'Barcode (${scannedThisMonth.barcode}) scanned for ${DateFormat('MMMM yyyy').format(now)}.',
          storeScannings: scannings,
        );
      } else {
        final barcodeList = scannings.map((s) => s.barcode).join(', ');
        return ScanningCheckResult(
          passed: false,
          status: 'Barcode(s) [$barcodeList] not yet scanned this month.',
          storeScannings: scannings,
        );
      }
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

  /// Marks the store PJP visit as completed and logs an audit transaction.
  Future<void> completeVisit({
    required String hapiStoreID,
    required Hapistore store,
    required String selectedDay,
  }) async {
    await _hapiStoreService.updateLastPjpVisit(hapiStoreID);
    await Helperfunctions.logTransaction(
      'PJP Visit Completed - ${store.storeName}',
      'Completed all 5 PJP criteria for $selectedDay',
      LogAction.update,
      page: AppPages.pjp,
    );
  }
}
