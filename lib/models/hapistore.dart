import 'package:cloud_firestore/cloud_firestore.dart';

class MerchBlitzStatus {
  static const String pendingSurvey = 'Pending Survey';
  static const String forFinalSurvey = 'For Final Survey';
  static const String surveyed = 'Surveyed';
}

class Hapistore {
  String storeName;
  String storeAddress;
  String storeContact;
  Timestamp? openingDate;
  String? pjpSchedule;
  Timestamp? lastPjpVisit;
  int? pjpSequence;
  double? latitude;
  double? longitude;
  Timestamp? lastMerchBlitzDate;
  String? merchBlitzStatus;
  String? storeUserUid;
  bool orderingEnabled;
  String? username;

  Hapistore({
    required this.storeName,
    required this.storeAddress,
    required this.storeContact,
    required this.openingDate,
    this.pjpSchedule,
    this.lastPjpVisit,
    this.pjpSequence,
    this.latitude,
    this.longitude,
    this.lastMerchBlitzDate,
    this.merchBlitzStatus,
    this.storeUserUid,
    this.orderingEnabled = true,
    this.username,
  });

  static Hapistore empty() =>
      Hapistore(
        storeName: '',
        storeAddress: '',
        storeContact: '',
        openingDate: null,
        pjpSchedule: null,
        lastPjpVisit: null,
        pjpSequence: null,
        latitude: null,
        longitude: null,
        lastMerchBlitzDate: null,
        merchBlitzStatus: null,
        storeUserUid: null,
        orderingEnabled: true,
        username: null,
      );

  factory Hapistore.fromJson(Map<String, Object?> json) {
    double? lat;
    double? lng;

    if (json['location'] is GeoPoint) {
      final geo = json['location'] as GeoPoint;
      lat = geo.latitude;
      lng = geo.longitude;
    } else if (json['latitude'] != null && json['longitude'] != null) {
      lat = (json['latitude'] as num?)?.toDouble();
      lng = (json['longitude'] as num?)?.toDouble();
    }

    return Hapistore(
      storeName: json['storeName'] as String? ?? '',
      storeAddress: json['storeAddress'] as String? ?? '',
      storeContact: json['storeContact'] as String? ?? '',
      openingDate: json['openingDate'] as Timestamp?,
      pjpSchedule: json['pjpSchedule'] as String?,
      lastPjpVisit: json['lastPjpVisit'] as Timestamp?,
      pjpSequence: json['pjpSequence'] as int?,
      latitude: lat,
      longitude: lng,
      lastMerchBlitzDate: json['lastMerchBlitzDate'] as Timestamp?,
      merchBlitzStatus: json['merchBlitzStatus'] as String?,
      storeUserUid: json['storeUserUid'] as String?,
      orderingEnabled: (json['orderingEnabled'] as bool?) ?? true,
      username: json['username'] as String?,
    );
  }

  factory Hapistore.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data()!;
      double? lat;
      double? lng;

      if (data['location'] is GeoPoint) {
        final geo = data['location'] as GeoPoint;
        lat = geo.latitude;
        lng = geo.longitude;
      } else if (data['latitude'] != null && data['longitude'] != null) {
        lat = (data['latitude'] as num?)?.toDouble();
        lng = (data['longitude'] as num?)?.toDouble();
      }

      return Hapistore(
        storeName: data['storeName'] ?? '',
        storeAddress: data['storeAddress'] ?? '',
        storeContact: data['storeContact'] ?? '',
        openingDate: data['openingDate'] as Timestamp?,
        pjpSchedule: data['pjpSchedule'] as String?,
        lastPjpVisit: data['lastPjpVisit'] as Timestamp?,
        pjpSequence: data['pjpSequence'] as int?,
        latitude: lat,
        longitude: lng,
        lastMerchBlitzDate: data['lastMerchBlitzDate'] as Timestamp?,
        merchBlitzStatus: data['merchBlitzStatus'] as String?,
        storeUserUid: data['storeUserUid'] as String?,
        orderingEnabled: (data['orderingEnabled'] as bool?) ?? true,
        username: data['username'] as String?,
      );
    } else {
      return Hapistore.empty();
    }
  }

  Hapistore copyWith({
    String? storeName,
    String? storeAddress,
    String? storeContact,
    Timestamp? openingDate,
    bool clearOpeningDate = false,
    String? pjpSchedule,
    Timestamp? lastPjpVisit,
    bool clearLastPjpVisit = false,
    int? pjpSequence,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    Timestamp? lastMerchBlitzDate,
    bool clearLastMerchBlitzDate = false,
    String? merchBlitzStatus,
    bool clearMerchBlitzStatus = false,
    String? storeUserUid,
    bool clearStoreUserUid = false,
    bool? orderingEnabled,
    String? username,
    bool clearUsername = false,
  }) {
    return Hapistore(
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeContact: storeContact ?? this.storeContact,
      openingDate: clearOpeningDate ? null : (openingDate ?? this.openingDate),
      pjpSchedule: pjpSchedule ?? this.pjpSchedule,
      lastPjpVisit: clearLastPjpVisit ? null : (lastPjpVisit ?? this.lastPjpVisit),
      pjpSequence: pjpSequence ?? this.pjpSequence,
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      lastMerchBlitzDate: clearLastMerchBlitzDate ? null : (lastMerchBlitzDate ?? this.lastMerchBlitzDate),
      merchBlitzStatus: clearMerchBlitzStatus ? null : (merchBlitzStatus ?? this.merchBlitzStatus),
      storeUserUid: clearStoreUserUid ? null : (storeUserUid ?? this.storeUserUid),
      orderingEnabled: orderingEnabled ?? this.orderingEnabled,
      username: clearUsername ? null : (username ?? this.username),
    );
  }

  String getMerchBlitzStatus(DateTime startDate, DateTime endDate) {
    if (lastMerchBlitzDate == null) {
      return MerchBlitzStatus.pendingSurvey;
    }
    final date = lastMerchBlitzDate!.toDate();
    final s = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final e = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    if (date.isBefore(s) || date.isAfter(e)) {
      return MerchBlitzStatus.pendingSurvey;
    }
    if (merchBlitzStatus == MerchBlitzStatus.forFinalSurvey) {
      return MerchBlitzStatus.forFinalSurvey;
    }
    if (merchBlitzStatus == MerchBlitzStatus.pendingSurvey) {
      return MerchBlitzStatus.pendingSurvey;
    }
    return MerchBlitzStatus.surveyed;
  }

  Map<String, Object?> toJson() {
    return {
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storeContact': storeContact,
      'openingDate': openingDate,
      'pjpSchedule': pjpSchedule,
      'lastPjpVisit': lastPjpVisit,
      'pjpSequence': pjpSequence,
      'latitude': latitude,
      'longitude': longitude,
      'lastMerchBlitzDate': lastMerchBlitzDate,
      'merchBlitzStatus': merchBlitzStatus,
      'storeUserUid': storeUserUid,
      'orderingEnabled': orderingEnabled,
      'username': username,
      'location': (latitude != null && longitude != null)
          ? GeoPoint(latitude!, longitude!)
          : null,
    };
  }
}
