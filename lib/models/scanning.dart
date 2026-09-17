import 'package:cloud_firestore/cloud_firestore.dart';

class Scanning {
  final String id;
  final String barcode;
  final String storeName;
  final Timestamp? scannedDate;
  final String scannedBy;
  final String status;

  Scanning({this.id = '', required this.barcode, required this.storeName, required this.scannedDate, required this.scannedBy, required this.status});

  static Scanning empty() => Scanning(barcode: '', storeName: '', scannedDate: null, scannedBy: '', status: '');

  Scanning.fromJson(Map<String, Object?> json)
    : this(
        id: json['id']! as String,
        barcode: json['barcode']! as String,
        storeName: json['storeName']! as String,
        scannedDate: json['scannedDate'] as Timestamp?,
        scannedBy: json['scannedBy']! as String,
        status: json['status']! as String,
      );

  factory Scanning.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Scanning(
        id: document.id,
        barcode: data?['barcode']! as String,
        storeName: data?['storeName']! as String,
        scannedDate: data?['scannedDate'] as Timestamp?,
        scannedBy: data?['scannedBy']! as String,
        status: data?['status']! as String,
      );
    } else {
      return Scanning.empty();
    }
  }

  Scanning copyWith({String? id, String? barcode, String? storeName, Timestamp? scannedDate, String? scannedBy, String? status}) {
    return Scanning(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      storeName: storeName ?? this.storeName,
      scannedDate: scannedDate ?? this.scannedDate,
      scannedBy: scannedBy ?? this.scannedBy,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'barcode': barcode, 'storeName': storeName, 'scannedDate': scannedDate, 'scannedBy': scannedBy, 'status': status};
  }
}
