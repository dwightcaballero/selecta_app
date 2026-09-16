import 'package:cloud_firestore/cloud_firestore.dart';

class Hapistore {
  String storeName;
  String storeAddress;
  String storeContact;
  Timestamp? openingDate;

  Hapistore({required this.storeName, required this.storeAddress, required this.storeContact, required this.openingDate});

  static Hapistore empty() => Hapistore(storeName: '', storeAddress: '', storeContact: '', openingDate: null);

  Hapistore.fromJson(Map<String, Object?> json)
    : this(
        storeName: json['storeName']! as String,
        storeAddress: json['storeAddress']! as String,
        storeContact: json['storeContact']! as String,
        openingDate: json['openingDate'] as Timestamp?,
      );

  factory Hapistore.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Hapistore(
        storeName: data?['storeName'] ?? '',
        storeAddress: data?['storeAddress'] ?? '',
        storeContact: data?['storeContact'] ?? '',
        openingDate: data?['openingDate'] as Timestamp?,
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
    String? storeNameSearch,
  }) {
    return Hapistore(
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeContact: storeContact ?? this.storeContact,
      openingDate: clearOpeningDate ? null : (openingDate ?? this.openingDate),
    );
  }

  Map<String, Object?> toJson() {
    return {'storeName': storeName, 'storeAddress': storeAddress, 'storeContact': storeContact, 'openingDate': openingDate};
  }
}
