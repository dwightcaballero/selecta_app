import 'package:cloud_firestore/cloud_firestore.dart';

class Placement {
  String storeName;
  String deliveryID;
  Timestamp deliveryDate;
  bool cotc1;
  bool cotc2;
  bool cotc3;
  bool cotc4;
  bool cotc5;
  bool cotc6;
  bool cotc7;
  bool cotc8;
  bool cotc9;
  bool cotc10;
  bool cotc11;
  bool cotc12;

  Placement({
    required this.storeName,
    required this.deliveryID,
    required this.deliveryDate,
    required this.cotc1,
    required this.cotc2,
    required this.cotc3,
    required this.cotc4,
    required this.cotc5,
    required this.cotc6,
    required this.cotc7,
    required this.cotc8,
    required this.cotc9,
    required this.cotc10,
    required this.cotc11,
    required this.cotc12,
  });

  Placement.fromJson(Map<String, Object?> json)
    : this(
        storeName: json['storeName']! as String,
        deliveryID: json['deliveryID']! as String,
        deliveryDate: json['deliveryDate']! as Timestamp,
        cotc1: json['cotc1']! as bool,
        cotc2: json['cotc2']! as bool,
        cotc3: json['cotc3']! as bool,
        cotc4: json['cotc4']! as bool,
        cotc5: json['cotc5']! as bool,
        cotc6: json['cotc6']! as bool,
        cotc7: json['cotc7']! as bool,
        cotc8: json['cotc8']! as bool,
        cotc9: json['cotc9']! as bool,
        cotc10: json['cotc10']! as bool,
        cotc11: json['cotc11']! as bool,
        cotc12: json['cotc12']! as bool,
      );

  factory Placement.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Placement(
        storeName: data?['storeName'] as String,
        deliveryID: data?['deliveryID'] as String,
        deliveryDate: data?['deliveryDate'] as Timestamp,
        cotc1: data?['cotc1'] as bool,
        cotc2: data?['cotc2'] as bool,
        cotc3: data?['cotc3'] as bool,
        cotc4: data?['cotc4'] as bool,
        cotc5: data?['cotc5'] as bool,
        cotc6: data?['cotc6'] as bool,
        cotc7: data?['cotc7'] as bool,
        cotc8: data?['cotc8'] as bool,
        cotc9: data?['cotc9'] as bool,
        cotc10: data?['cotc10'] as bool,
        cotc11: data?['cotc11'] as bool,
        cotc12: data?['cotc12'] as bool,
      );
    } else {
      return Placement.empty();
    }
  }

  static Placement empty() => Placement(
    storeName: '',
    deliveryID: '',
    deliveryDate: Timestamp.now(),
    cotc1: false,
    cotc2: false,
    cotc3: false,
    cotc4: false,
    cotc5: false,
    cotc6: false,
    cotc7: false,
    cotc8: false,
    cotc9: false,
    cotc10: false,
    cotc11: false,
    cotc12: false,
  );

  factory Placement.fromFlags({required String storeName, required String deliveryID, required Timestamp deliveryDate, required List<bool> flags}) {
    assert(flags.length == 12);
    return Placement(
      storeName: storeName,
      deliveryID: deliveryID,
      deliveryDate: deliveryDate,
      cotc1: flags[0],
      cotc2: flags[1],
      cotc3: flags[2],
      cotc4: flags[3],
      cotc5: flags[4],
      cotc6: flags[5],
      cotc7: flags[6],
      cotc8: flags[7],
      cotc9: flags[8],
      cotc10: flags[9],
      cotc11: flags[10],
      cotc12: flags[11],
    );
  }

  Placement copyWith({
    String? storeName,
    String? deliveryID,
    Timestamp? deliveryDate,
    bool? cotc1,
    bool? cotc2,
    bool? cotc3,
    bool? cotc4,
    bool? cotc5,
    bool? cotc6,
    bool? cotc7,
    bool? cotc8,
    bool? cotc9,
    bool? cotc10,
    bool? cotc11,
    bool? cotc12,
  }) {
    return Placement(
      storeName: storeName ?? this.storeName,
      deliveryID: deliveryID ?? this.deliveryID,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      cotc1: cotc1 ?? this.cotc1,
      cotc2: cotc2 ?? this.cotc2,
      cotc3: cotc3 ?? this.cotc3,
      cotc4: cotc4 ?? this.cotc4,
      cotc5: cotc5 ?? this.cotc5,
      cotc6: cotc6 ?? this.cotc6,
      cotc7: cotc7 ?? this.cotc7,
      cotc8: cotc8 ?? this.cotc8,
      cotc9: cotc9 ?? this.cotc9,
      cotc10: cotc10 ?? this.cotc10,
      cotc11: cotc11 ?? this.cotc11,
      cotc12: cotc12 ?? this.cotc12,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'storeName': storeName,
      'deliveryID': deliveryID,
      'deliveryDate': deliveryDate,
      'cotc1': cotc1,
      'cotc2': cotc2,
      'cotc3': cotc3,
      'cotc4': cotc4,
      'cotc5': cotc5,
      'cotc6': cotc6,
      'cotc7': cotc7,
      'cotc8': cotc8,
      'cotc9': cotc9,
      'cotc10': cotc10,
      'cotc11': cotc11,
      'cotc12': cotc12,
    };
  }
}
