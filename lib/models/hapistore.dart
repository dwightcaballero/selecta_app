import 'package:cloud_firestore/cloud_firestore.dart';

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
    );
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
      if (latitude != null && longitude != null)
        'location': GeoPoint(latitude!, longitude!),
    };
  }
}
