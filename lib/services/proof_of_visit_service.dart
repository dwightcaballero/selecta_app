import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';

// ignore: constant_identifier_names
const String PROOF_OF_VISIT_COLLECTION = 'proof_of_visit';

class ProofOfVisitService {
  final FirebaseFirestore _firestore;

  ProofOfVisitService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<ProofOfVisit> get _collection => _firestore
      .collection(PROOF_OF_VISIT_COLLECTION)
      .withConverter<ProofOfVisit>(fromFirestore: (snapshot, _) => ProofOfVisit.fromSnapshot(snapshot), toFirestore: (proof, _) => proof.toJson());

  /// Saves a new Proof of Visit record in Firestore.
  Future<String> addProofOfVisit(ProofOfVisit proof) async {
    final docRef = await _collection.add(proof);
    return docRef.id;
  }

  /// Checks if a proof of visit photo was taken for the given store today.
  Future<ProofOfVisit?> getProofOfVisitForStoreToday(String storeName) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final snapshot = await _collection
          .where('storeName', isEqualTo: storeName)
          .where('visitDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('visitDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('visitDate', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
    } catch (_) {
      // Fallback in case composite index is still building: query store and filter in memory
      try {
        final snapshot = await _collection.where('storeName', isEqualTo: storeName).limit(10).get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final dt = data.visitDate.toDate();
          if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
            return data;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Retrieves all proof of visit records for a specific store.
  Future<List<ProofOfVisit>> getProofsOfVisitByStore(String storeName) async {
    final snapshot = await _collection.where('storeName', isEqualTo: storeName).orderBy('visitDate', descending: true).get();

    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// Realtime stream of all proof of visit records, ordered by visit date descending.
  Stream<List<ProofOfVisit>> getAllProofsOfVisitStream() {
    return _collection.orderBy('visitDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
