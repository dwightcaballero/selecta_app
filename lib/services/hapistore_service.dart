import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/configuration_service.dart';

// ignore: constant_identifier_names
const String HAPISTORE_COLLECTION_REF = 'hapistores';

class HapiStoreService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _hapistoresRef;

  HapiStoreService() {
    _hapistoresRef = _firestore
        .collection(HAPISTORE_COLLECTION_REF)
        .withConverter<Hapistore>(
          fromFirestore: (snapshots, _) => Hapistore.fromJson(snapshots.data()!),
          toFirestore: (hapistore, _) => hapistore.toJson(),
        );
  }

  static List<Hapistore>? cachedStores;

  static void invalidateCache() {
    cachedStores = null;
  }

  void addHapiStore(Hapistore hapistore) {
    invalidateCache();
    _hapistoresRef.add(hapistore);
  }

  void updateHapiStore(String hapiStoreID, Hapistore hapistore) {
    invalidateCache();
    _hapistoresRef.doc(hapiStoreID).update(hapistore.toJson());
  }

  Future<void> updateMerchBlitzStatus(
    String hapiStoreID, {
    required String status,
    Timestamp? timestamp,
  }) async {
    invalidateCache();
    await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(hapiStoreID).update({
      'merchBlitzStatus': status,
      'lastMerchBlitzDate': timestamp,
    });
  }

  Future<void> updateLastMerchBlitzDate(String hapiStoreID, Timestamp? timestamp) async {
    invalidateCache();
    await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(hapiStoreID).update({
      'lastMerchBlitzDate': timestamp,
      'merchBlitzStatus': timestamp == null ? MerchBlitzStatus.pendingSurvey : MerchBlitzStatus.surveyed,
    });
  }

  Future<void> updateLastPjpVisit(String hapiStoreID, [Timestamp? timestamp]) async {
    invalidateCache();
    await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(hapiStoreID).update({
      'lastPjpVisit': timestamp ?? Timestamp.now(),
    });
  }

  Future<Hapistore?> getHapiStoreById(String hapiStoreID) async {
    final doc = await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(hapiStoreID).get();
    if (!doc.exists || doc.data() == null) return null;
    return Hapistore.fromJson(doc.data()!);
  }

  void deleteHapiStore(String hapiStoreID) {
    invalidateCache();
    _hapistoresRef.doc(hapiStoreID).delete();
  }

  Stream<QuerySnapshot> getListHapiStoresAsStream() {
    return _hapistoresRef.orderBy('storeName').snapshots().map((snapshot) {
      cachedStores = snapshot.docs.map((doc) {
        final data = doc.data();
        if (data is Hapistore) return data;
        return Hapistore.fromJson(data as Map<String, Object?>);
      }).toList();
      return snapshot;
    });
  }

  Stream<QuerySnapshot> getListHapiStoreSearch(String searchKeyword) {
    return _hapistoresRef
        .orderBy('storeName')
        .where('storeName', isGreaterThanOrEqualTo: searchKeyword)
        .where('storeName', isLessThanOrEqualTo: '$searchKeyword\uf8ff')
        .snapshots();
  }

  static Future<String> getContactByStoreName(String storeName) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(HAPISTORE_COLLECTION_REF)
          .where('storeName', isEqualTo: storeName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var result = querySnapshot.docs.map((doc) {
          return Hapistore.fromJson(doc.data() as Map<String, dynamic>);
        }).first;
        return result.storeContact;
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  // Get list hapi stores as a Future (not stream) with in-memory caching
  static Future<List<Hapistore>> getListHapiStores({bool forceRefresh = false}) async {
    if (!forceRefresh && cachedStores != null) {
      return cachedStores!;
    }
    var snapshot = await FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).orderBy('storeName').get();
    cachedStores = snapshot.docs.map((doc) => Hapistore.fromJson(doc.data())).toList();
    return cachedStores!;
  }

  // Get list of hapi stores with opening date within the current month
  static Future<List<Hapistore>> getListHapiStoresWithOpeningDateInCurrentMonth() async {
    var now = DateTime.now();
    var firstDayOfMonth = DateTime(now.year, now.month, 1);
    var lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(HAPISTORE_COLLECTION_REF)
        .where('openingDate', isGreaterThanOrEqualTo: firstDayOfMonth)
        .where('openingDate', isLessThanOrEqualTo: lastDayOfMonth)
        .get();

    return snapshot.docs.map((doc) => Hapistore.fromJson(doc.data())).toList();
  }

  // Get list of stores opened within the past 3 months
  static Future<List<Hapistore>> getListHapiStoresOpenedWithinPastThreeMonths() async {
    var now = DateTime.now();
    var threeMonthsAgo = DateTime(now.year, now.month - 3, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(HAPISTORE_COLLECTION_REF)
        .where('openingDate', isGreaterThanOrEqualTo: threeMonthsAgo)
        .get();

    return snapshot.docs.map((doc) => Hapistore.fromJson(doc.data())).toList();
  }

  static Future<List<Hapistore>> getListHapiStoresBasedOnPJPSchedule(String pjpSchedule) async {
    var snapshot = await FirebaseFirestore.instance
        .collection(HAPISTORE_COLLECTION_REF)
        .where('pjpSchedule', isEqualTo: pjpSchedule)
        .orderBy('pjpSequence')
        .get();

    return snapshot.docs.map((doc) => Hapistore.fromJson(doc.data())).toList();
  }

  // No orderBy here: Firestore excludes docs missing the pjpSequence field from ordered queries,
  // which would hide stores that haven't been sequenced yet. Sorting is done client-side instead.
  Stream<QuerySnapshot> getListHapiStoresByPjpScheduleAsStream(String pjpSchedule) {
    return _hapistoresRef.where('pjpSchedule', isEqualTo: pjpSchedule).snapshots();
  }

  // Persists a new store order for a PJP day, writing sequential pjpSequence values and the day's
  // pjpSchedule (so stores newly added to the day from elsewhere get reassigned) in a single batch.
  // Stores removed from the day have their pjpSchedule/pjpSequence cleared instead.
  Future<void> updatePjpSequenceOrder(String pjpSchedule, List<String> orderedHapiStoreIDs, {List<String> removedHapiStoreIDs = const []}) async {
    invalidateCache();
    final batch = _firestore.batch();
    for (var i = 0; i < orderedHapiStoreIDs.length; i++) {
      batch.update(_hapistoresRef.doc(orderedHapiStoreIDs[i]), {'pjpSchedule': pjpSchedule, 'pjpSequence': i});
    }
    for (final hapiStoreID in removedHapiStoreIDs) {
      batch.update(_hapistoresRef.doc(hapiStoreID), {'pjpSchedule': null, 'pjpSequence': null});
    }
    await batch.commit();
  }

  // Count stores scheduled for today that haven't been visited yet this week
  static int countPendingPjpVisitsForToday(List<Hapistore> stores, [DateTime? date]) {
    final now = date ?? DateTime.now();
    final todayName = PjpScheduleDays.all[now.weekday - 1];
    return stores.where((store) {
      final isTodaySchedule = store.pjpSchedule?.trim().toLowerCase() == todayName.toLowerCase();
      if (!isTodaySchedule) return false;
      final isVisitedThisWeek = store.lastPjpVisit != null &&
          Helperfunctions.isSameWeek(store.lastPjpVisit!.toDate(), now);
      return !isVisitedThisWeek;
    }).length;
  }

  static Future<int> getPendingPjpVisitCountForToday() async {
    final stores = await getListHapiStores();
    return countPendingPjpVisitsForToday(stores);
  }

  Stream<int> getUnsurveyedMerchBlitzCountStream({bool forDealer = false}) {
    final controller = StreamController<int>.broadcast();
    Configuration? currentConfig;
    QuerySnapshot? currentStoresSnapshot;

    void emitCount() {
      if (controller.isClosed) return;
      if (currentConfig == null || currentStoresSnapshot == null) {
        return;
      }
      final startDate = currentConfig!.merchBlitzStartDate.toDate();
      final endDate = currentConfig!.merchBlitzEndDate.toDate();

      final now = DateTime.now();
      final s = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
      final e = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

      // If today is not in between start date and end date, do not show a badge (count = 0)
      if (now.isBefore(s) || now.isAfter(e)) {
        controller.add(0);
        return;
      }

      int count = 0;
      for (final doc in currentStoresSnapshot!.docs) {
        final data = doc.data();
        final store = data is Hapistore ? data : Hapistore.fromJson(data as Map<String, Object?>);
        final status = store.getMerchBlitzStatus(startDate, endDate);
        if (forDealer) {
          if (status == MerchBlitzStatus.forFinalSurvey) {
            count++;
          }
        } else {
          if (status == MerchBlitzStatus.pendingSurvey) {
            count++;
          }
        }
      }
      controller.add(count);
    }

    StreamSubscription? configSub;
    StreamSubscription? storesSub;

    controller.onListen = () {
      configSub = ConfigurationService().getConfigurationStream().listen((cfg) {
        currentConfig = cfg ?? Configuration.empty();
        emitCount();
      });
      storesSub = _hapistoresRef.snapshots().listen((snap) {
        currentStoresSnapshot = snap;
        emitCount();
      });
    };

    controller.onCancel = () {
      configSub?.cancel();
      storesSub?.cancel();
    };

    return controller.stream;
  }
}
