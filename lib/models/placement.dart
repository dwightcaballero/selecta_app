import 'package:cloud_firestore/cloud_firestore.dart';

class Placement {
  String id;
  String storeName;
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
  bool isFinished;
  int progressCount;

  Placement({
    required this.id,
    required this.storeName,
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
    required this.isFinished,
    required this.progressCount,
  });

  Placement.fromJson(Map<String, Object?> json)
    : this(
        id: json['id']! as String,
        storeName: json['storeName']! as String,
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
        isFinished: json['isFinished']! as bool,
        progressCount: json['progressCount']! as int,
      );

  factory Placement.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Placement(
        id: data?['id'] as String,
        storeName: data?['storeName'] as String,
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
        isFinished: data?['isFinished'] as bool,
        progressCount: data?['progressCount'] as int,
      );
    } else {
      return Placement.empty();
    }
  }

  static Placement empty() => Placement(
    id: '',
    storeName: '',
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
    isFinished: false,
    progressCount: 0,
  );

  factory Placement.fromFlags({required String id, required String storeName, required Timestamp deliveryDate, required List<bool> flags}) {
    assert(flags.length == 12);
    return Placement(
      id: id,
      storeName: storeName,
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
      isFinished: false,
      progressCount: 0,
    );
  }

  Placement copyWith({
    String? id,
    String? storeName,
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
    bool? isFinished,
    int? progressCount,
  }) {
    return Placement(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
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
      isFinished: isFinished ?? this.isFinished,
      progressCount: progressCount ?? this.progressCount,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'storeName': storeName,
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
      'isFinished': isFinished,
      'progressCount': progressCount,
    };
  }
}
