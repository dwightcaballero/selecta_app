import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/attendance.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('attendances');

  static String formatDate(DateTime dt) => _dateFormatter.format(dt);

  static String makeDocId(String dateString, String username) =>
      'att_${dateString}_${username.trim()}';

  /// Normalizes a DateTime to start of day (midnight)
  static DateTime normalizeToStartOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// Fetches an attendance record for a salesman on a specific date (defaults to today)
  Future<Attendance?> getAttendanceForDate({
    required String salesmanUsername,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final dateString = formatDate(targetDate);
    final docId = makeDocId(dateString, salesmanUsername);

    final snapshot = await _collection.doc(docId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return Attendance.fromSnapshot(snapshot);
  }

  /// Streams an attendance record for a salesman on a specific date (defaults to today)
  Stream<Attendance?> streamAttendanceForDate({
    required String salesmanUsername,
    DateTime? date,
  }) {
    final targetDate = date ?? DateTime.now();
    final dateString = formatDate(targetDate);
    final docId = makeDocId(dateString, salesmanUsername);

    return _collection.doc(docId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return Attendance.fromSnapshot(snapshot);
    });
  }

  /// Submits Clock-In for a salesman
  Future<Attendance> clockIn({
    required String salesmanUsername,
    required String salesmanFullName,
    required String dealerName,
    required DateTime time,
    double? latitude,
    double? longitude,
    double? distanceToDepot,
    bool withinGeofence = false,
  }) async {
    final dateString = formatDate(time);
    final docId = makeDocId(dateString, salesmanUsername);
    final docRef = _collection.doc(docId);

    final existingDoc = await docRef.get();
    final now = Timestamp.fromDate(time);

    if (existingDoc.exists && existingDoc.data() != null) {
      final existing = Attendance.fromSnapshot(existingDoc);
      if (existing.isClockedIn) {
        // Already clocked in, return existing
        return existing;
      }
    }

    final newAttendance = Attendance(
      id: docId,
      dealerName: dealerName,
      salesmanUsername: salesmanUsername,
      salesmanFullName: salesmanFullName,
      date: Timestamp.fromDate(normalizeToStartOfDay(time)),
      dateString: dateString,
      clockInTime: now,
      clockInLatitude: latitude,
      clockInLongitude: longitude,
      clockInDistanceToDepot: distanceToDepot,
      clockInWithinGeofence: withinGeofence,
      clockInStatus: AttendanceStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(newAttendance.toJson(), SetOptions(merge: true));
    return newAttendance;
  }

  /// Submits Clock-Out for a salesman
  Future<Attendance> clockOut({
    required String salesmanUsername,
    required DateTime time,
    double? latitude,
    double? longitude,
    double? distanceToDepot,
    bool withinGeofence = false,
  }) async {
    final dateString = formatDate(time);
    final docId = makeDocId(dateString, salesmanUsername);
    final docRef = _collection.doc(docId);

    final existingDoc = await docRef.get();
    if (!existingDoc.exists || existingDoc.data() == null) {
      throw Exception('Cannot clock out without clocking in first.');
    }

    final existing = Attendance.fromSnapshot(existingDoc);
    if (existing.clockInTime == null) {
      throw Exception('Cannot clock out without clocking in first.');
    }

    final now = Timestamp.fromDate(time);
    final totalHours = Attendance.computeHours(existing.clockInTime!, now);
    final dayCredit = Attendance.calculateStandardCredit(totalHours);

    final updated = existing.copyWith(
      clockOutTime: now,
      clockOutLatitude: latitude,
      clockOutLongitude: longitude,
      clockOutDistanceToDepot: distanceToDepot,
      clockOutWithinGeofence: withinGeofence,
      clockOutStatus: AttendanceStatus.pending,
      totalHours: totalHours,
      dayCredit: dayCredit,
      isCompleted: true,
      updatedAt: now,
    );

    await docRef.set(updated.toJson(), SetOptions(merge: true));
    return updated;
  }

  /// Fetches list of salesmen who clocked in on [date] for [dealerName] but have not yet clocked out.
  Future<List<Attendance>> getUnclockedSalesmenForDate({
    required String dealerName,
    required DateTime date,
  }) async {
    final dateString = formatDate(date);
    final snapshot = await _collection
        .where('dealerName', isEqualTo: dealerName)
        .where('dateString', isEqualTo: dateString)
        .get();

    final list = snapshot.docs
        .map((d) => Attendance.fromSnapshot(d))
        .where((a) => a.isClockedIn && !a.isClockedOut)
        .toList();

    return list;
  }

  /// Streams all attendances for a dealer on a specific date
  Stream<List<Attendance>> streamAttendancesForDate({
    required String dealerName,
    required DateTime date,
  }) {
    final dateString = formatDate(date);
    return _collection
        .where('dealerName', isEqualTo: dealerName)
        .where('dateString', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => Attendance.fromSnapshot(d)).toList()
              ..sort((a, b) =>
                  (a.clockInTime?.millisecondsSinceEpoch ?? 0)
                      .compareTo(b.clockInTime?.millisecondsSinceEpoch ?? 0)));
  }

  /// Streams pending approvals count for a dealer today
  Stream<int> streamPendingApprovalsCount({
    required String dealerName,
    required DateTime date,
  }) {
    final dateString = formatDate(date);
    return _collection
        .where('dealerName', isEqualTo: dealerName)
        .where('dateString', isEqualTo: dateString)
        .snapshots()
        .map((snapshot) {
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final inStatus = data['clockInStatus'] as String?;
        final outStatus = data['clockOutStatus'] as String?;
        final hasClockOut = data['clockOutTime'] != null;
        if (inStatus == AttendanceStatus.pending) count++;
        if (hasClockOut && outStatus == AttendanceStatus.pending) count++;
      }
      return count;
    });
  }

  /// Approves a clock-in record
  Future<void> approveClockIn({
    required String attendanceId,
    required String dealerUsername,
  }) async {
    await _collection.doc(attendanceId).update({
      'clockInStatus': AttendanceStatus.approved,
      'clockInApprovedBy': dealerUsername,
      'clockInApprovedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Approves a clock-out record
  Future<void> approveClockOut({
    required String attendanceId,
    required String dealerUsername,
  }) async {
    await _collection.doc(attendanceId).update({
      'clockOutStatus': AttendanceStatus.approved,
      'clockOutApprovedBy': dealerUsername,
      'clockOutApprovedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Batch approves all pending clock-ins and clock-outs for [date]
  Future<int> batchApproveAll({
    required String dealerName,
    required DateTime date,
    required String dealerUsername,
  }) async {
    final dateString = formatDate(date);
    final snapshot = await _collection
        .where('dealerName', isEqualTo: dealerName)
        .where('dateString', isEqualTo: dateString)
        .get();

    final batch = _firestore.batch();
    int count = 0;

    for (final doc in snapshot.docs) {
      final a = Attendance.fromSnapshot(doc);
      final updates = <String, dynamic>{};
      if (a.isClockedIn && a.clockInStatus == AttendanceStatus.pending) {
        updates['clockInStatus'] = AttendanceStatus.approved;
        updates['clockInApprovedBy'] = dealerUsername;
        updates['clockInApprovedAt'] = FieldValue.serverTimestamp();
      }
      if (a.isClockedOut && a.clockOutStatus == AttendanceStatus.pending) {
        updates['clockOutStatus'] = AttendanceStatus.approved;
        updates['clockOutApprovedBy'] = dealerUsername;
        updates['clockOutApprovedAt'] = FieldValue.serverTimestamp();
      }
      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        batch.update(doc.reference, updates);
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  /// Fetches weekly attendances for a salesman in date range (inclusive)
  Future<List<Attendance>> getWeeklyAttendances({
    required String salesmanUsername,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startNormalized = normalizeToStartOfDay(startDate);
    final endNormalized = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    final snapshot = await _collection
        .where('salesmanUsername', isEqualTo: salesmanUsername)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startNormalized))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endNormalized))
        .get();

    return snapshot.docs.map((d) => Attendance.fromSnapshot(d)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Allows dealer to override a day credit with custom remarks
  Future<void> overrideDayCredit({
    required String attendanceId,
    required double newCredit,
    String? remarks,
    required String dealerUsername,
  }) async {
    await _collection.doc(attendanceId).update({
      'dealerOverrideCredit': newCredit,
      'overrideRemarks': remarks,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
