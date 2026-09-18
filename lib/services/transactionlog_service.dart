import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/notifiers.dart';
import 'package:flutter_app/models/transactionlog.dart';

// ignore: constant_identifier_names
const String LOG_COLLECTION_REF = 'transactionlogs';

class TransactionLogService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _logRef;

  TransactionLogService() {
    _logRef = _firestore
        .collection(LOG_COLLECTION_REF)
        .withConverter<TransactionLog>(
          fromFirestore: (snapshots, _) => TransactionLog.fromJson(snapshots.data()!),
          toFirestore: (log, _) => log.toJson(),
        );
  }

  Stream<QuerySnapshot> getListLogs() {
    return _logRef.orderBy('loggedDate', descending: true).snapshots();
  }

  Stream<QuerySnapshot> getLogsLastSevenDays() {
    DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    DateTime startOfDay = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);
    DateTime endOfDay = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day, 23, 59, 59);

    try {
      Query query = _logRef
          .where('loggedDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('loggedDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('loggedDate', descending: true);

      return query.snapshots();
    } catch (e) {
      return Stream.empty();
    }
  }

  Stream<QuerySnapshot> getLogsForDay(DateTime day) {
    DateTime startOfDay = DateTime(day.year, day.month, day.day);
    DateTime endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);

    try {
      Query query = _logRef
          .where('loggedDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('loggedDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('loggedDate', descending: true);

      return query.snapshots();
    } catch (e) {
      return Stream.empty();
    }
  }

  Future<void> addLog(TransactionLog log) async {
    await _logRef.add(log);
    dashboardNeedsRefreshNotifier.value = true;
  }

  void updateLog(String logID, TransactionLog log) {
    _logRef.doc(logID).update(log.toJson());
  }

  void deleteLog(String logID) {
    _logRef.doc(logID).delete();
  }
}
