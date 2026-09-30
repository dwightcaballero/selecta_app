import 'package:cloud_firestore/cloud_firestore.dart';

class Scanning {
  final String id;
  final String barcode;
  final String storeName;
  final Timestamp? scannedDate;
  final String scannedBy;
  final String status;
  final String imageUrl;

  Scanning({
    this.id = '',
    required this.barcode,
    required this.storeName,
    required this.scannedDate,
    required this.scannedBy,
    required this.status,
    this.imageUrl = '',
  });

  static Scanning empty() => Scanning(barcode: '', storeName: '', scannedDate: null, scannedBy: '', status: '', imageUrl: '');

  Scanning.fromJson(Map<String, Object?> json)
    : this(
        id: (json['id'] as String? ?? '').trim(),
        barcode: (json['barcode'] as String? ?? '').trim(),
        storeName: (json['storeName'] as String? ?? '').trim(),
        scannedDate: json['scannedDate'] as Timestamp?,
        scannedBy: (json['scannedBy'] as String? ?? '').trim(),
        status: (json['status'] as String? ?? '').trim(),
        imageUrl: ((json['imageUrl'] ?? json['freezerImageUrl']) as String? ?? '').trim(),
      );

  factory Scanning.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Scanning(
        id: document.id,
        barcode: (data?['barcode'] as String? ?? '').trim(),
        storeName: (data?['storeName'] as String? ?? '').trim(),
        scannedDate: data?['scannedDate'] as Timestamp?,
        scannedBy: (data?['scannedBy'] as String? ?? '').trim(),
        status: (data?['status'] as String? ?? '').trim(),
        imageUrl: ((data?['imageUrl'] ?? data?['freezerImageUrl']) as String? ?? '').trim(),
      );
    } else {
      return Scanning.empty();
    }
  }

  Scanning copyWith({
    String? id,
    String? barcode,
    String? storeName,
    Timestamp? scannedDate,
    bool clearScannedDate = false,
    String? scannedBy,
    String? status,
    String? imageUrl,
  }) {
    return Scanning(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      storeName: storeName ?? this.storeName,
      scannedDate: clearScannedDate ? null : (scannedDate ?? this.scannedDate),
      scannedBy: scannedBy ?? this.scannedBy,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'storeName': storeName,
      'scannedDate': scannedDate,
      'scannedBy': scannedBy,
      'status': status,
      'imageUrl': imageUrl,
    };
  }
}
