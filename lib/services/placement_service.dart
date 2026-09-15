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

  Future<String> addPlacement(Placement placement) async {
    final documentReference = await _placementsRef.add(placement);
    return documentReference.id;
  }

  void updatePlacement(String placementID, Placement placement) {
    _placementsRef.doc(placementID).update(placement.toJson());
  }

  void deletePlacement(String placementID) {
    _placementsRef.doc(placementID).delete();
  }

  // Delete placement by delivery ID
  Future<void> deletePlacementByDeliveryID(String deliveryID) async {
    final querySnapshot = await _placementsRef.where('deliveryID', isEqualTo: deliveryID).get();
    final batch = _firestore.batch();
    for (final doc in querySnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // Get list of placement within the current month and store name
  Future<List<Placement>> getPlacementsWithinCurrentMonth(String storeName) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

      final snapshot = await _placementsRef
          .where('storeName', isEqualTo: storeName)
          .where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('deliveryDate', isLessThan: Timestamp.fromDate(startOfNextMonth))
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return [];
    }
  }
}
