import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/scout_route_track.dart';
import 'package:selecta_ops/services/error_log_service.dart';

// ignore: constant_identifier_names
const String SCOUT_ROUTES_COLLECTION = 'scout_routes';

class ScoutTrackingService {
  static final ScoutTrackingService _instance = ScoutTrackingService._internal();
  factory ScoutTrackingService() => _instance;
  ScoutTrackingService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _collectionRef =>
      _firestore.collection(SCOUT_ROUTES_COLLECTION);

  StreamSubscription<Position>? _positionSub;
  Timer? _flushTimer;

  // Active state
  final ValueNotifier<bool> isTrackingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> recordedPointsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> distanceTraveledNotifier = ValueNotifier<double>(0.0); // in meters

  String? _currentSessionId;
  String _currentSalesmanName = 'Salesman';
  final List<ScoutTrackPoint> _sessionPoints = [];
  Position? _lastRecordedPos;

  bool get isTracking => isTrackingNotifier.value;
  int get recordedPoints => recordedPointsNotifier.value;
  double get distanceMeters => distanceTraveledNotifier.value;
  String get currentSalesmanName => _currentSalesmanName;

  /// Start recording the salesman's route
  Future<bool> startTracking({required String salesmanName}) async {
    if (isTracking) return true;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      _currentSalesmanName = salesmanName;
      _sessionPoints.clear();
      recordedPointsNotifier.value = 0;
      distanceTraveledNotifier.value = 0.0;
      _lastRecordedPos = null;

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      // Create new session in Firestore
      final docRef = await _collectionRef.add({
        'salesmanName': salesmanName,
        'dateString': dateStr,
        'startedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'isActive': true,
        'points': [],
      });

      _currentSessionId = docRef.id;
      isTrackingNotifier.value = true;

      // Start GPS location stream
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 12, // Record point every 12 meters
      );

      _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(_onPositionUpdate, onError: (err) {
        ErrorLogService.logError(
          action: 'ScoutTracking_PositionStream',
          error: err.toString(),
          page: 'ScoutTrackingService',
        );
      });

      // Periodic flush timer every 15 seconds
      _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flushPointsToFirestore());

      return true;
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'startTracking',
        error: e.toString(),
        stackTrace: stack,
        page: 'ScoutTrackingService',
      );
      isTrackingNotifier.value = false;
      return false;
    }
  }

  void _onPositionUpdate(Position pos) {
    if (!isTracking) return;

    // Calculate incremental distance if previous point exists
    if (_lastRecordedPos != null) {
      final d = Geolocator.distanceBetween(
        _lastRecordedPos!.latitude,
        _lastRecordedPos!.longitude,
        pos.latitude,
        pos.longitude,
      );
      distanceTraveledNotifier.value += d;
    }
    _lastRecordedPos = pos;

    final pt = ScoutTrackPoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: DateTime.now(),
    );

    _sessionPoints.add(pt);
    recordedPointsNotifier.value = _sessionPoints.length;

    // Flush immediately if buffer reaches 5 points
    if (_sessionPoints.length % 5 == 0) {
      _flushPointsToFirestore();
    }
  }

  Future<void> _flushPointsToFirestore() async {
    if (_currentSessionId == null || _sessionPoints.isEmpty) return;
    try {
      await _collectionRef.doc(_currentSessionId).update({
        'points': _sessionPoints.map((p) => p.toJson()).toList(),
        'distanceMeters': distanceTraveledNotifier.value,
      });
    } catch (_) {}
  }

  /// Stop tracking route
  Future<void> stopTracking() async {
    if (!isTracking) return;

    _positionSub?.cancel();
    _positionSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;

    final sessionId = _currentSessionId;
    final finalDistance = distanceTraveledNotifier.value;
    _currentSessionId = null;
    isTrackingNotifier.value = false;

    if (sessionId != null) {
      try {
        await _collectionRef.doc(sessionId).update({
          'points': _sessionPoints.map((p) => p.toJson()).toList(),
          'endedAt': FieldValue.serverTimestamp(),
          'distanceMeters': finalDistance,
          'isActive': false,
        });
      } catch (e) {
        ErrorLogService.logError(
          action: 'stopTracking',
          error: e.toString(),
          page: 'ScoutTrackingService',
        );
      }
    }
  }

  /// Delete a recorded scout route session
  Future<void> deleteRoute(String sessionId) async {
    try {
      await _collectionRef.doc(sessionId).delete();
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'deleteRoute',
        error: e.toString(),
        stackTrace: stack,
        page: 'ScoutTrackingService',
      );
    }
  }

  /// Mark or unmark a route as needing to be re-scouted by the salesman
  Future<void> toggleMarkForRescout(String sessionId, bool needsRescout) async {
    try {
      await _collectionRef.doc(sessionId).update({
        'needsRescout': needsRescout,
        'markedForRescoutAt': needsRescout ? FieldValue.serverTimestamp() : null,
      });
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'toggleMarkForRescout',
        error: e.toString(),
        stackTrace: stack,
        page: 'ScoutTrackingService',
      );
    }
  }

  /// Get real-time stream of scout routes for a specific date (defaults to today)
  Stream<List<ScoutRouteSession>> getRoutesStream({String? dateString}) {
    final queryDate = dateString ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _collectionRef
        .where('dateString', isEqualTo: queryDate)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ScoutRouteSession.fromSnapshot(doc))
          .toList();
    }).handleError((err) {
      return <ScoutRouteSession>[];
    });
  }

  /// Get stream of routes filtered by date range or recency tier
  Stream<List<ScoutRouteSession>> getRoutesStreamByRange({
    DateTime? startDate,
    DateTime? endDate,
    bool onlyDueForRescout = false,
  }) {
    return _collectionRef
        .orderBy('startedAt', descending: true)
        .limit(150)
        .snapshots()
        .map((snapshot) {
      var list = snapshot.docs
          .map((doc) => ScoutRouteSession.fromSnapshot(doc))
          .toList();

      if (onlyDueForRescout) {
        list = list.where((r) => r.recencyTier == RecencyTier.stale || r.needsRescout).toList();
      } else if (startDate != null && endDate != null) {
        final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
        final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        list = list.where((r) => r.startedAt.isAfter(start) && r.startedAt.isBefore(end)).toList();
      }
      return list;
    }).handleError((err) {
      return <ScoutRouteSession>[];
    });
  }

  /// Get stream of all recent routes (e.g. past 7 days)
  Stream<List<ScoutRouteSession>> getAllRecentRoutesStream() {
    return _collectionRef
        .orderBy('startedAt', descending: true)
        .limit(60)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ScoutRouteSession.fromSnapshot(doc))
          .toList();
    }).handleError((err) {
      return <ScoutRouteSession>[];
    });
  }
}
