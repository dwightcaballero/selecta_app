import 'package:cloud_firestore/cloud_firestore.dart';

// ignore: constant_identifier_names
const String PJP_ORDER_DECISIONS_COLLECTION = 'pjp_order_decisions';

class PjpOrderDecision {
  final String id;
  final String storeName;
  final String decision; // e.g. 'no_order'
  final String reason;
  final Timestamp date;
  final String createdBy;
  final Timestamp createdAt;

  PjpOrderDecision({
    this.id = '',
    required this.storeName,
    required this.decision,
    required this.reason,
    required this.date,
    this.createdBy = '',
    Timestamp? createdAt,
  }) : createdAt = createdAt ?? Timestamp.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeName': storeName,
    'decision': decision,
    'reason': reason,
    'date': date,
    'createdBy': createdBy,
    'createdAt': createdAt,
  };

  factory PjpOrderDecision.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PjpOrderDecision(
      id: doc.id,
      storeName: (data['storeName'] as String? ?? '').trim(),
      decision: (data['decision'] as String? ?? '').trim(),
      reason: (data['reason'] as String? ?? '').trim(),
      date: data['date'] as Timestamp? ?? Timestamp.now(),
      createdBy: (data['createdBy'] as String? ?? '').trim(),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }
}

class PjpOrderDecisionService {
  final FirebaseFirestore _firestore;

  PjpOrderDecisionService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore.collection(PJP_ORDER_DECISIONS_COLLECTION);

  /// Saves a decision (e.g. no order booked with required reason) for a store.
  Future<String> recordNoOrderReason({required String storeName, required String reason, required String createdBy}) async {
    final docRef = await _collection.add({
      'storeName': storeName,
      'decision': 'no_order',
      'reason': reason.trim(),
      'date': Timestamp.now(),
      'createdBy': createdBy,
      'createdAt': Timestamp.now(),
    });
    return docRef.id;
  }

  /// Checks if a 'no_order' decision was recorded for this store today.
  Future<PjpOrderDecision?> getTodayNoOrderDecision(String storeName) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final snapshot = await _collection
          .where('storeName', isEqualTo: storeName)
          .where('decision', isEqualTo: 'no_order')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('date', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return PjpOrderDecision.fromSnapshot(snapshot.docs.first);
      }
    } catch (_) {
      try {
        final snapshot = await _collection.where('storeName', isEqualTo: storeName).where('decision', isEqualTo: 'no_order').limit(10).get();

        for (final doc in snapshot.docs) {
          final decision = PjpOrderDecision.fromSnapshot(doc);
          final dt = decision.date.toDate();
          if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
            return decision;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Records that the store ordered via POS+ (external Android app).
  /// No Delivery record is created — this is purely a PJP pass-through flag.
  Future<String> recordOrderedInPosPlus({
    required String storeName,
    required String createdBy,
  }) async {
    final docRef = await _collection.add({
      'storeName': storeName,
      'decision': 'ordered_in_pos_plus',
      'reason': 'Ordered in POS+',
      'date': Timestamp.now(),
      'createdBy': createdBy,
      'createdAt': Timestamp.now(),
    });
    return docRef.id;
  }

  /// Checks if an 'ordered_in_pos_plus' decision was recorded for this store today.
  Future<PjpOrderDecision?> getTodayPosOrderDecision(String storeName) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final snapshot = await _collection
          .where('storeName', isEqualTo: storeName)
          .where('decision', isEqualTo: 'ordered_in_pos_plus')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('date', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return PjpOrderDecision.fromSnapshot(snapshot.docs.first);
      }
    } catch (_) {
      try {
        final snapshot = await _collection
            .where('storeName', isEqualTo: storeName)
            .where('decision', isEqualTo: 'ordered_in_pos_plus')
            .limit(10)
            .get();

        for (final doc in snapshot.docs) {
          final decision = PjpOrderDecision.fromSnapshot(doc);
          final dt = decision.date.toDate();
          if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
            return decision;
          }
        }
      } catch (_) {}
    }
    return null;
  }
}
