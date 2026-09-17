import 'package:cloud_firestore/cloud_firestore.dart';

class Hapistore {
  String storeName;
  String storeAddress;
  String storeContact;
  Timestamp? openingDate;
  String? pjpSchedule;
  Timestamp? lastPjpVisit;
  int? pjpSequence;

  Hapistore({
    required this.storeName,
    required this.storeAddress,
    required this.storeContact,
    required this.openingDate,
    this.pjpSchedule,
    this.lastPjpVisit,
    this.pjpSequence,
  });

  static Hapistore empty() =>
      Hapistore(storeName: '', storeAddress: '', storeContact: '', openingDate: null, pjpSchedule: null, lastPjpVisit: null, pjpSequence: null);

  Hapistore.fromJson(Map<String, Object?> json)
    : this(
        storeName: json['storeName'] as String? ?? '',
        storeAddress: json['storeAddress'] as String? ?? '',
        storeContact: json['storeContact'] as String? ?? '',
        openingDate: json['openingDate'] as Timestamp?,
        pjpSchedule: json['pjpSchedule'] as String?,
        lastPjpVisit: json['lastPjpVisit'] as Timestamp?,
        pjpSequence: json['pjpSequence'] as int?,
      );

  factory Hapistore.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Hapistore(
        storeName: data?['storeName'] ?? '',
        storeAddress: data?['storeAddress'] ?? '',
        storeContact: data?['storeContact'] ?? '',
        openingDate: data?['openingDate'] as Timestamp?,
        pjpSchedule: data?['pjpSchedule'] as String?,
        lastPjpVisit: data?['lastPjpVisit'] as Timestamp?,
        pjpSequence: data?['pjpSequence'] as int?,
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
  }) {
    return Hapistore(
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeContact: storeContact ?? this.storeContact,
      openingDate: clearOpeningDate ? null : (openingDate ?? this.openingDate),
      pjpSchedule: pjpSchedule ?? this.pjpSchedule,
      lastPjpVisit: clearLastPjpVisit ? null : (lastPjpVisit ?? this.lastPjpVisit),
      pjpSequence: pjpSequence ?? this.pjpSequence,
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
    };
  }
}
