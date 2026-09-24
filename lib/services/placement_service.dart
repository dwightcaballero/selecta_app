import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import '../models/placement.dart';

// ignore: constant_identifier_names
const String PLACEMENT_COLLECTION_REF = 'placement';

class PlacementService {
  PlacementService() {
    _placementsRef = _firestore
        .collection(PLACEMENT_COLLECTION_REF)
        .withConverter<Placement>(
          fromFirestore: (snapshots, _) => Placement.fromJson(snapshots.data()!),
          toFirestore: (placement, _) => placement.toJson(),
        );
  }

  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Placement> _placementsRef;

  // Save placement record if it doesnt exist in the database. Else, update the existing record.
  Future<void> savePlacement(Placement placement) async {
    if (placement.id.isEmpty) {
      final existing = await getPlacementByStoreAndDate(placement.storeName, placement.deliveryDate.toDate());
      if (existing != null) {
        placement.id = existing.id;
        await _placementsRef.doc(placement.id).set(placement, SetOptions(merge: true));
        return;
      }
      final docRef = _placementsRef.doc();
      placement.id = docRef.id;
      await docRef.set(placement);
    } else {
      await _placementsRef.doc(placement.id).set(placement, SetOptions(merge: true));
    }
  }

  // Get 1 placement record by store name and delivery date within the month
  Future<Placement?> getPlacementByStoreAndDate(String storeName, DateTime deliveryDate) async {
    try {
      final startOfMonth = DateTime(deliveryDate.year, deliveryDate.month, 1);
      final startOfNextMonth = DateTime(deliveryDate.year, deliveryDate.month + 1, 1);

      final snapshot = await _placementsRef
          .where('storeName', isEqualTo: storeName)
          .where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('deliveryDate', isLessThan: Timestamp.fromDate(startOfNextMonth))
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        var placement = snapshot.docs.first.data();
        placement.id = snapshot.docs.first.id;
        return placement;
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // Get list of all placement records within the current month\
  static Future<List<Placement>> getListOfPlacementsWithinCurrentMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    final snapshot = await FirebaseFirestore.instance
        .collection(PLACEMENT_COLLECTION_REF)
        .where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('deliveryDate', isLessThan: Timestamp.fromDate(startOfNextMonth))
        .get();

    return snapshot.docs.map((doc) {
      var placement = Placement.fromJson(doc.data());
      placement.id = doc.id;
      return placement;
    }).toList();
  }

  // Get count of all placement records with finished status in current month
  static Future<int> getCountOfFinishedPlacements() async {
    final list = await getListOfPlacementsWithinCurrentMonth();
    return list.where((placement) => placement.isFinished).length;
  }

  static Future<List<Placement>> getListPlacementForAllStores() async {
    var listStores = await HapiStoreService.getListHapiStores();
    var listPlacements = await getListOfPlacementsWithinCurrentMonth();
    List<Placement> finalList = [];
    for (var store in listStores) {
      Placement? placement = listPlacements.where((placement) => placement.storeName == store.storeName).firstOrNull;

      if (placement != null) {
        finalList.add(placement);
      } else {
        var tempPlacement = Placement.empty();
        tempPlacement.storeName = store.storeName;
        finalList.add(tempPlacement);
      }
    }
    return finalList;
  }
}
