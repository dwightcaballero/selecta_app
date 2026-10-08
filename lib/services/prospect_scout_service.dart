import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/prospect_scout.dart';
import 'package:selecta_ops/services/error_log_service.dart';

// ignore: constant_identifier_names
const String PROSPECT_SCOUTS_COLLECTION = 'prospect_scouts';

class ProspectScoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collectionRef =>
      _firestore.collection(PROSPECT_SCOUTS_COLLECTION);

  /// Real-time stream of all prospects, sorted by creation date descending
  Stream<List<ProspectScout>> getProspectScoutsStream() {
    return _collectionRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ProspectScout.fromSnapshot(doc))
          .toList();
    }).handleError((error, stackTrace) {
      ErrorLogService.logError(
        action: 'getProspectScoutsStream',
        error: error.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      return <ProspectScout>[];
    });
  }

  /// Single fetch of all prospects
  Future<List<ProspectScout>> getAllProspectScouts() async {
    try {
      final snapshot = await _collectionRef
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ProspectScout.fromSnapshot(doc))
          .toList();
    } catch (e, stackTrace) {
      ErrorLogService.logError(
        action: 'getAllProspectScouts',
        error: e.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      return [];
    }
  }

  /// Add a new prospect scout record
  Future<String> addProspectScout(ProspectScout scout) async {
    try {
      final docRef = await _collectionRef.add(scout.toJson());
      return docRef.id;
    } catch (e, stackTrace) {
      ErrorLogService.logError(
        action: 'addProspectScout',
        error: e.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      rethrow;
    }
  }

  /// Update an existing prospect record
  Future<void> updateProspectScout(String id, ProspectScout scout) async {
    try {
      await _collectionRef.doc(id).update(scout.toJson());
    } catch (e, stackTrace) {
      ErrorLogService.logError(
        action: 'updateProspectScout',
        error: e.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      rethrow;
    }
  }

  /// Update only the status of a prospect (Scouted -> Engaged -> Converted)
  Future<void> updateProspectStatus(String id, String newStatus) async {
    try {
      await _collectionRef.doc(id).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stackTrace) {
      ErrorLogService.logError(
        action: 'updateProspectStatus',
        error: e.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      rethrow;
    }
  }

  /// Delete a prospect record
  Future<void> deleteProspectScout(String id) async {
    try {
      await _collectionRef.doc(id).delete();
    } catch (e, stackTrace) {
      ErrorLogService.logError(
        action: 'deleteProspectScout',
        error: e.toString(),
        stackTrace: stackTrace,
        page: 'ProspectScoutService',
      );
      rethrow;
    }
  }
}
