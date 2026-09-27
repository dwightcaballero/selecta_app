import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:geolocator/geolocator.dart';

/// Controller responsible for HapiStore business logic, filtering,
/// geolocation fetching, and data operations with audit logging.
class HapiStoreController {
  final HapiStoreService _service = HapiStoreService();

  /// Returns real-time stream of all registered Hapi Stores.
  Stream<QuerySnapshot> getHapiStoresStream() {
    return _service.getListHapiStoresAsStream();
  }

  /// Returns cached stores if available in memory.
  List<Hapistore>? get cachedStores => HapiStoreService.cachedStores;

  /// Returns real-time stream of parsed Hapistore objects.
  Stream<List<Hapistore>> getHapiStoresListStream() {
    return _service.getListHapiStoresAsStream().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        if (data is Hapistore) return data;
        return Hapistore.fromJson(data as Map<String, Object?>);
      }).toList();
    });
  }

  /// Checks if current user possesses dealer permissions.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Filters store snapshots based on PJP schedule day and search keywords.
  List<QueryDocumentSnapshot> filterStores({
    required List<QueryDocumentSnapshot> docs,
    required String selectedPjpDay,
    required String searchQuery,
  }) {
    return docs.where((doc) {
      final rawData = doc.data();
      final hapistore = rawData is Hapistore
          ? rawData
          : Hapistore.fromJson(rawData as Map<String, Object?>);

      // 1. PJP day filter
      if (selectedPjpDay != 'All') {
        if (selectedPjpDay == 'Unscheduled') {
          if (hapistore.pjpSchedule != null && hapistore.pjpSchedule!.trim().isNotEmpty) {
            return false;
          }
        } else {
          if (hapistore.pjpSchedule?.trim().toLowerCase() != selectedPjpDay.toLowerCase()) {
            return false;
          }
        }
      }

      // 2. Search query filter (Store Name, Address, Contact)
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final nameMatch = hapistore.storeName.toLowerCase().contains(query);
        final addressMatch = hapistore.storeAddress.toLowerCase().contains(query);
        final contactMatch = hapistore.storeContact.contains(query);
        if (!nameMatch && !addressMatch && !contactMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Obtains current GPS coordinates with permission checks.
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Adds a new Hapi Store and writes an audit log.
  Future<void> addStore(Hapistore store) async {
    _service.addHapiStore(store);
    Helperfunctions.logCreate(
      store.storeName,
      store.toJson(),
      page: AppPages.hapiStore,
    );
  }

  /// Updates an existing Hapi Store and writes an audit log with change diff.
  Future<void> updateStore({
    required String id,
    required Hapistore oldStore,
    required Hapistore updatedStore,
  }) async {
    _service.updateHapiStore(id, updatedStore);
    Helperfunctions.logUpdate(
      updatedStore.storeName,
      oldStore.toJson(),
      updatedStore.toJson(),
      page: AppPages.hapiStore,
    );
  }

  /// Deletes a Hapi Store and writes an audit log.
  Future<void> deleteStore({
    required String id,
    required Hapistore store,
  }) async {
    _service.deleteHapiStore(id);
    Helperfunctions.logDelete(
      store.storeName,
      store.toJson(),
      page: AppPages.hapiStore,
    );
  }
}
