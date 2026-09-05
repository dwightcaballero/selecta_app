import 'package:cloud_firestore/cloud_firestore.dart';

class BadOrder {
  String description;
  String hapistore;
  double badorderAmount;
  Timestamp badorderDate;
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;

  BadOrder({
    required this.description,
    required this.hapistore,
    required this.badorderAmount,
    required this.badorderDate,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
  });

  static BadOrder empty() => BadOrder(
    description: '',
    hapistore: '',
    badorderAmount: 0,
    badorderDate: Timestamp.now(),
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
  );

  BadOrder.fromJson(Map<String, Object?> json)
    : this(
        description: json['description']! as String,
        hapistore: json['hapistore']! as String,
        badorderAmount: json['badorderAmount']! as double,
        badorderDate: json['badorderDate']! as Timestamp,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
      );

  factory BadOrder.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      final data = document.data();
      return BadOrder(
        description: data?['description'],
        hapistore: data?['hapistore'],
        badorderAmount: data?['badorderAmount'],
        badorderDate: data?['badorderDate'],
        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate'],
      );
    } else {
      return BadOrder.empty();
    }
  }

  BadOrder copyWith({
    String? description,
    String? hapistore,
    double? badorderAmount,
    Timestamp? badorderDate,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
  }) {
    return BadOrder(
      description: description ?? this.description,
      hapistore: hapistore ?? this.hapistore,
      badorderAmount: badorderAmount ?? this.badorderAmount,
      badorderDate: badorderDate ?? this.badorderDate,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'description': description,
      'hapistore': hapistore,
      'badorderAmount': badorderAmount,
      'badorderDate': badorderDate,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
    };
  }
}
