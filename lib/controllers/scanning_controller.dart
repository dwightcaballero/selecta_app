import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/scanning_services.dart';

/// Sorting criteria for scanning list items.
enum ScanningSort {
  storeNameAscending,
  storeNameDescending,
  barcodeAscending,
  barcodeDescending,
  scannedDateAscending,
  scannedDateDescending,
}

/// Controller responsible for managing barcode freezer scanning records,
/// store assignments, list filtering, sorting, and Firestore persistence.
class ScanningController {
  final ScanningServices _scanningService;

  ScanningController({ScanningServices? scanningService})
      : _scanningService = scanningService ?? ScanningServices();

  // ==========================================
  // List Operations (ScanninglistPage)
  // ==========================================

  /// Loads all scanning records and stores, building the store lookup map
  /// and injecting unassigned stores that do not yet have barcodes.
  Future<({List<Scanning> scannings, Map<String, Hapistore> storesMap})> loadScanningData() async {
    final results = await Future.wait([
      ScanningServices.getAllScannings(),
      HapiStoreService.getListHapiStores(forceRefresh: true),
    ]);

    final scannings = results[0] as List<Scanning>;
    final stores = results[1] as List<Hapistore>;

    final storesMap = <String, Hapistore>{};
    final assignedStoreNames = <String>{};

    for (final store in stores) {
      if (store.storeName.trim().isNotEmpty) {
        storesMap[store.storeName.trim().toLowerCase()] = store;
      }
    }

    for (final s in scannings) {
      if (s.barcode.trim().isNotEmpty && s.status != ScanningStatus.pullout && s.storeName.trim().isNotEmpty) {
        assignedStoreNames.add(s.storeName.trim().toLowerCase());
      }
    }

    final combinedList = List<Scanning>.from(scannings);

    // Identify unassigned stores (stores with no barcode saved in the database)
    for (final store in stores) {
      final name = store.storeName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!assignedStoreNames.contains(key)) {
        final alreadyInList = combinedList.any(
          (s) => s.status == ScanningStatus.unassigned && s.storeName.trim().toLowerCase() == key,
        );
        if (!alreadyInList) {
          combinedList.add(
            Scanning(
              id: '',
              barcode: '',
              storeName: store.storeName,
              scannedDate: null,
              scannedBy: '',
              status: ScanningStatus.unassigned,
            ),
          );
        }
      }
    }

    return (scannings: combinedList, storesMap: storesMap);
  }

  /// Filters scanning records by tab status and search query, then sorts the result.
  List<Scanning> filterAndSortScannings({
    required List<Scanning> scannings,
    required Map<String, Hapistore> storesMap,
    required String status,
    required String searchQuery,
    required ScanningSort sort,
  }) {
    List<Scanning> filtered = scannings.where((s) => s.status == status).toList();
    final query = searchQuery.trim().toLowerCase();

    if (query.isNotEmpty) {
      filtered = filtered.where((scanning) {
        final store = storesMap[scanning.storeName.trim().toLowerCase()];
        final address = store?.storeAddress.toLowerCase() ?? '';
        final contact = store?.storeContact.toLowerCase() ?? '';
        return scanning.storeName.toLowerCase().contains(query) ||
            scanning.barcode.toLowerCase().contains(query) ||
            address.contains(query) ||
            contact.contains(query);
      }).toList();
    }

    filtered.sort((first, second) => compareScannings(first, second, sort));
    return filtered;
  }

  /// Comparator logic to order two [Scanning] records according to [ScanningSort].
  int compareScannings(Scanning first, Scanning second, ScanningSort sort) {
    final comparison = switch (sort) {
      ScanningSort.storeNameAscending ||
      ScanningSort.storeNameDescending =>
        first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      ScanningSort.barcodeAscending ||
      ScanningSort.barcodeDescending =>
        first.barcode.compareTo(second.barcode) != 0
            ? first.barcode.compareTo(second.barcode)
            : first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      ScanningSort.scannedDateAscending ||
      ScanningSort.scannedDateDescending =>
        first.scannedDate == null
            ? (second.scannedDate == null ? first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()) : -1)
            : (second.scannedDate == null ? 1 : first.scannedDate!.compareTo(second.scannedDate!)),
    };

    return switch (sort) {
      ScanningSort.storeNameDescending ||
      ScanningSort.barcodeDescending ||
      ScanningSort.scannedDateDescending =>
        -comparison,
      _ => comparison,
    };
  }

  // ==========================================
  // Detail Operations (ScanningPage)
  // ==========================================

  /// Checks if the logged-in user is a dealer.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Fetches an existing scanning record by barcode.
  Future<Scanning?> getScanningByBarcode(String barcode) async {
    return await _scanningService.getScanningByBarcode(barcode);
  }

  /// Saves or updates a scanning record and creates audit logs.
  Future<Scanning> saveScanningRecord({
    required Scanning existing,
    required String barcode,
    required String storeName,
    required String status,
    String? imageUrl,
    bool isDealer = false,
  }) async {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) {
      throw Exception('Barcode cannot be empty.');
    }

    // Role check: Only dealers are authorized to mark a barcode as scanned
    if (status == ScanningStatus.scanned && !isDealer) {
      throw Exception('Only dealers are authorized to mark a barcode as scanned.');
    }

    final existingInDb = await _scanningService.getScanningByBarcode(trimmedBarcode);
    if (existing.id.isEmpty && existingInDb != null) {
      throw Exception('Barcode "$trimmedBarcode" already exists in the database.');
    }
    if (existing.id.isNotEmpty && existingInDb != null && existingInDb.id != existing.id) {
      throw Exception('Barcode "$trimmedBarcode" already exists in the database.');
    }

    String finalImageUrl = (imageUrl != null && imageUrl.trim().isNotEmpty) ? imageUrl.trim() : existing.imageUrl.trim();

    // Photo check: When scanning to Pending or Scanned, freezer photo is required
    if ((status == ScanningStatus.pending || status == ScanningStatus.scanned) && finalImageUrl.isEmpty) {
      throw Exception('A picture of the freezer is required for this month upon scanning.');
    }

    String scannedBy = '';
    String finalStoreName = storeName;
    Timestamp? scannedDate;

    switch (status) {
      case ScanningStatus.notScanned:
        scannedDate = null;
        scannedBy = '';
        finalImageUrl = '';
        break;
      case ScanningStatus.pending:
      case ScanningStatus.scanned:
        scannedDate = Timestamp.now();
        scannedBy = authService.value.currentUser?.displayName ?? '';
        break;
      case ScanningStatus.pullout:
        scannedDate = Timestamp.now();
        scannedBy = '';
        finalStoreName = '';
        finalImageUrl = '';
        break;
      default:
        scannedDate = existing.scannedDate;
        scannedBy = existing.scannedBy;
    }

    final newRecord = Scanning(
      id: existing.id,
      barcode: trimmedBarcode,
      storeName: finalStoreName,
      scannedDate: scannedDate,
      scannedBy: scannedBy,
      status: status,
      imageUrl: (status == ScanningStatus.notScanned || status == ScanningStatus.pullout) ? '' : finalImageUrl,
    );

    final bool isNewRecord = existing.id.isEmpty;
    await _scanningService.saveScanning(newRecord);

    if (isNewRecord) {
      await Helperfunctions.logCreate(newRecord.storeName, newRecord.toJson(), page: AppPages.scanning);
    } else {
      await Helperfunctions.logUpdate(newRecord.storeName, existing.toJson(), newRecord.toJson(), page: AppPages.scanning);
    }

    return newRecord;
  }

  /// Deletes a scanning record and logs an audit transaction.
  Future<void> deleteScanningRecord(Scanning scanning) async {
    await _scanningService.deleteScanning(scanning.id);
    await Helperfunctions.logDelete(scanning.storeName, scanning.toJson(), page: AppPages.scanning);
  }
}
