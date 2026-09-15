import 'package:cloud_firestore/cloud_firestore.dart';
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
      await _placementsRef.add(placement);
    } else {
      await _placementsRef.doc(placement.id).update(placement.toJson());
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

  // Get count of all placement records with finished status
  static Future<int> getCountOfFinishedPlacements() async {
    final snapshot = await FirebaseFirestore.instance.collection(PLACEMENT_COLLECTION_REF).where('isFinished', isEqualTo: true).get();
    return snapshot.docs.length;
  }
}
