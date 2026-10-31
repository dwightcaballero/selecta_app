import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
}

class Attendance {
  String id;
  String dealerName;
  String salesmanUsername;
  String salesmanFullName;
  Timestamp date;
  String dateString; // 'YYYY-MM-DD'

  // Clock In
  Timestamp? clockInTime;
  double? clockInLatitude;
  double? clockInLongitude;
  double? clockInDistanceToDepot;
  bool clockInWithinGeofence;
  String clockInStatus;
  String? clockInApprovedBy;
  Timestamp? clockInApprovedAt;

  // Clock Out
  Timestamp? clockOutTime;
  double? clockOutLatitude;
  double? clockOutLongitude;
  double? clockOutDistanceToDepot;
  bool clockOutWithinGeofence;
  String clockOutStatus;
  String? clockOutApprovedBy;
  Timestamp? clockOutApprovedAt;

  // Payroll & Summary
  double totalHours;
  double dayCredit;
  double? dealerOverrideCredit;
  String? overrideRemarks;
  bool isCompleted;
  Timestamp? createdAt;
  Timestamp? updatedAt;

  Attendance({
    required this.id,
    required this.dealerName,
    required this.salesmanUsername,
    required this.salesmanFullName,
    required this.date,
    required this.dateString,
    this.clockInTime,
    this.clockInLatitude,
    this.clockInLongitude,
    this.clockInDistanceToDepot,
    this.clockInWithinGeofence = false,
    this.clockInStatus = AttendanceStatus.pending,
    this.clockInApprovedBy,
    this.clockInApprovedAt,
    this.clockOutTime,
    this.clockOutLatitude,
    this.clockOutLongitude,
    this.clockOutDistanceToDepot,
    this.clockOutWithinGeofence = false,
    this.clockOutStatus = AttendanceStatus.pending,
    this.clockOutApprovedBy,
    this.clockOutApprovedAt,
    this.totalHours = 0.0,
    this.dayCredit = 0.0,
    this.dealerOverrideCredit,
    this.overrideRemarks,
    this.isCompleted = false,
    this.createdAt,
    this.updatedAt,
  });

  bool get isClockedIn => clockInTime != null;
  bool get isClockedOut => clockOutTime != null;
  bool get isClockInApproved => clockInStatus == AttendanceStatus.approved;
  bool get isClockOutApproved => clockOutStatus == AttendanceStatus.approved;
  double get effectiveCredit => dealerOverrideCredit ?? dayCredit;

  /// Calculates standard day credit based on hours worked:
  /// >= 6.0 hours -> 1.0 day
  /// 4.0 to < 6.0 hours -> 0.5 day
  /// < 4.0 hours -> 0.0 day
  static double calculateStandardCredit(double hours) {
    if (hours >= 6.0) {
      return 1.0;
    } else if (hours >= 4.0) {
      return 0.5;
    } else {
      return 0.0;
    }
  }

  /// Calculates duration between two timestamps in hours
  static double computeHours(Timestamp start, Timestamp end) {
    final diffMs = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    if (diffMs <= 0) return 0.0;
    return double.parse((diffMs / (1000 * 60 * 60)).toStringAsFixed(2));
  }

  factory Attendance.empty() => Attendance(
        id: '',
        dealerName: '',
        salesmanUsername: '',
        salesmanFullName: '',
        date: Timestamp.now(),
        dateString: '',
      );

  factory Attendance.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Attendance.fromJson(data, id: doc.id);
  }

  factory Attendance.fromJson(Map<String, dynamic> json, {String? id}) {
    return Attendance(
      id: id ?? (json['id'] as String? ?? ''),
      dealerName: json['dealerName'] as String? ?? '',
      salesmanUsername: json['salesmanUsername'] as String? ?? '',
      salesmanFullName: json['salesmanFullName'] as String? ?? '',
      date: json['date'] as Timestamp? ?? Timestamp.now(),
      dateString: json['dateString'] as String? ?? '',
      clockInTime: json['clockInTime'] as Timestamp?,
      clockInLatitude: (json['clockInLatitude'] as num?)?.toDouble(),
      clockInLongitude: (json['clockInLongitude'] as num?)?.toDouble(),
      clockInDistanceToDepot: (json['clockInDistanceToDepot'] as num?)?.toDouble(),
      clockInWithinGeofence: json['clockInWithinGeofence'] as bool? ?? false,
      clockInStatus: json['clockInStatus'] as String? ?? AttendanceStatus.pending,
      clockInApprovedBy: json['clockInApprovedBy'] as String?,
      clockInApprovedAt: json['clockInApprovedAt'] as Timestamp?,
      clockOutTime: json['clockOutTime'] as Timestamp?,
      clockOutLatitude: (json['clockOutLatitude'] as num?)?.toDouble(),
      clockOutLongitude: (json['clockOutLongitude'] as num?)?.toDouble(),
      clockOutDistanceToDepot: (json['clockOutDistanceToDepot'] as num?)?.toDouble(),
      clockOutWithinGeofence: json['clockOutWithinGeofence'] as bool? ?? false,
      clockOutStatus: json['clockOutStatus'] as String? ?? AttendanceStatus.pending,
      clockOutApprovedBy: json['clockOutApprovedBy'] as String?,
      clockOutApprovedAt: json['clockOutApprovedAt'] as Timestamp?,
      totalHours: (json['totalHours'] as num?)?.toDouble() ?? 0.0,
      dayCredit: (json['dayCredit'] as num?)?.toDouble() ?? 0.0,
      dealerOverrideCredit: (json['dealerOverrideCredit'] as num?)?.toDouble(),
      overrideRemarks: json['overrideRemarks'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: json['createdAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dealerName': dealerName,
      'salesmanUsername': salesmanUsername,
      'salesmanFullName': salesmanFullName,
      'date': date,
      'dateString': dateString,
      'clockInTime': clockInTime,
      'clockInLatitude': clockInLatitude,
      'clockInLongitude': clockInLongitude,
      'clockInDistanceToDepot': clockInDistanceToDepot,
      'clockInWithinGeofence': clockInWithinGeofence,
      'clockInStatus': clockInStatus,
      'clockInApprovedBy': clockInApprovedBy,
      'clockInApprovedAt': clockInApprovedAt,
      'clockOutTime': clockOutTime,
      'clockOutLatitude': clockOutLatitude,
      'clockOutLongitude': clockOutLongitude,
      'clockOutDistanceToDepot': clockOutDistanceToDepot,
      'clockOutWithinGeofence': clockOutWithinGeofence,
      'clockOutStatus': clockOutStatus,
      'clockOutApprovedBy': clockOutApprovedBy,
      'clockOutApprovedAt': clockOutApprovedAt,
      'totalHours': totalHours,
      'dayCredit': dayCredit,
      'dealerOverrideCredit': dealerOverrideCredit,
      'overrideRemarks': overrideRemarks,
      'isCompleted': isCompleted,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Attendance copyWith({
    String? id,
    String? dealerName,
    String? salesmanUsername,
    String? salesmanFullName,
    Timestamp? date,
    String? dateString,
    Timestamp? clockInTime,
    double? clockInLatitude,
    double? clockInLongitude,
    double? clockInDistanceToDepot,
    bool? clockInWithinGeofence,
    String? clockInStatus,
    String? clockInApprovedBy,
    Timestamp? clockInApprovedAt,
    Timestamp? clockOutTime,
    double? clockOutLatitude,
    double? clockOutLongitude,
    double? clockOutDistanceToDepot,
    bool? clockOutWithinGeofence,
    String? clockOutStatus,
    String? clockOutApprovedBy,
    Timestamp? clockOutApprovedAt,
    double? totalHours,
    double? dayCredit,
    double? dealerOverrideCredit,
    String? overrideRemarks,
    bool? isCompleted,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return Attendance(
      id: id ?? this.id,
      dealerName: dealerName ?? this.dealerName,
      salesmanUsername: salesmanUsername ?? this.salesmanUsername,
      salesmanFullName: salesmanFullName ?? this.salesmanFullName,
      date: date ?? this.date,
      dateString: dateString ?? this.dateString,
      clockInTime: clockInTime ?? this.clockInTime,
      clockInLatitude: clockInLatitude ?? this.clockInLatitude,
      clockInLongitude: clockInLongitude ?? this.clockInLongitude,
      clockInDistanceToDepot: clockInDistanceToDepot ?? this.clockInDistanceToDepot,
      clockInWithinGeofence: clockInWithinGeofence ?? this.clockInWithinGeofence,
      clockInStatus: clockInStatus ?? this.clockInStatus,
      clockInApprovedBy: clockInApprovedBy ?? this.clockInApprovedBy,
      clockInApprovedAt: clockInApprovedAt ?? this.clockInApprovedAt,
      clockOutTime: clockOutTime ?? this.clockOutTime,
      clockOutLatitude: clockOutLatitude ?? this.clockOutLatitude,
      clockOutLongitude: clockOutLongitude ?? this.clockOutLongitude,
      clockOutDistanceToDepot: clockOutDistanceToDepot ?? this.clockOutDistanceToDepot,
      clockOutWithinGeofence: clockOutWithinGeofence ?? this.clockOutWithinGeofence,
      clockOutStatus: clockOutStatus ?? this.clockOutStatus,
      clockOutApprovedBy: clockOutApprovedBy ?? this.clockOutApprovedBy,
      clockOutApprovedAt: clockOutApprovedAt ?? this.clockOutApprovedAt,
      totalHours: totalHours ?? this.totalHours,
      dayCredit: dayCredit ?? this.dayCredit,
      dealerOverrideCredit: dealerOverrideCredit ?? this.dealerOverrideCredit,
      overrideRemarks: overrideRemarks ?? this.overrideRemarks,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
