import 'package:cloud_firestore/cloud_firestore.dart';

class Placement {
  String id;
  String storeName;
  Timestamp deliveryDate;
  List<String> placedProductNames;
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
    this.placedProductNames = const [],
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

  factory Placement.fromJson(Map<String, Object?> json) {
    final rawPlaced = json['placedProductNames'];
    List<String> parsedPlaced = [];
    if (rawPlaced is List) {
      parsedPlaced = rawPlaced.map((e) => e.toString()).toList();
    } else {
      // Backward compatibility: If placedProductNames is absent, populate from legacy cotc flags
      final legacyFlags = [
        json['cotc1'] == true,
        json['cotc2'] == true,
        json['cotc3'] == true,
        json['cotc4'] == true,
        json['cotc5'] == true,
        json['cotc6'] == true,
        json['cotc7'] == true,
        json['cotc8'] == true,
        json['cotc9'] == true,
        json['cotc10'] == true,
        json['cotc11'] == true,
        json['cotc12'] == true,
      ];
      final legacyNames = [
        "Watermelon Slice",
        "Chocky Stick",
        "Avocado Choco",
        "Boom Boom Choco",
        "Cornetto Choco",
        "Cornetto Cookies & Dream",
        "Bday 3in1 C-K-U",
        "Bday 3in1 U-M-A",
        "Bday 3+1 C-K-U-M",
        "Sup Double Dutch",
        "Sup Rocky Road",
        "Sup Cookies & Cream",
      ];
      for (int i = 0; i < legacyNames.length && i < legacyFlags.length; i++) {
        if (legacyFlags[i]) {
          parsedPlaced.add(legacyNames[i]);
        }
      }
    }

    return Placement(
      id: (json['id'] as String?) ?? '',
      storeName: (json['storeName'] as String?) ?? '',
      deliveryDate: (json['deliveryDate'] as Timestamp?) ?? Timestamp.now(),
      placedProductNames: parsedPlaced,
      cotc1: (json['cotc1'] as bool?) ?? false,
      cotc2: (json['cotc2'] as bool?) ?? false,
      cotc3: (json['cotc3'] as bool?) ?? false,
      cotc4: (json['cotc4'] as bool?) ?? false,
      cotc5: (json['cotc5'] as bool?) ?? false,
      cotc6: (json['cotc6'] as bool?) ?? false,
      cotc7: (json['cotc7'] as bool?) ?? false,
      cotc8: (json['cotc8'] as bool?) ?? false,
      cotc9: (json['cotc9'] as bool?) ?? false,
      cotc10: (json['cotc10'] as bool?) ?? false,
      cotc11: (json['cotc11'] as bool?) ?? false,
      cotc12: (json['cotc12'] as bool?) ?? false,
      isFinished: (json['isFinished'] as bool?) ?? false,
      progressCount: (json['progressCount'] as int?) ?? 0,
    );
  }

  factory Placement.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data()!;
      final id = data['id'] as String? ?? document.id;
      final map = Map<String, Object?>.from(data)..['id'] = id;
      return Placement.fromJson(map);
    } else {
      return Placement.empty();
    }
  }

  static Placement empty() => Placement(
    id: '',
    storeName: '',
    deliveryDate: Timestamp.now(),
    placedProductNames: const [],
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

  factory Placement.fromFlags({
    required String id,
    required String storeName,
    required Timestamp deliveryDate,
    required List<bool> flags,
    List<String>? placedProductNames,
  }) {
    assert(flags.length == 12);
    final legacyNames = [
      "Watermelon Slice",
      "Chocky Stick",
      "Avocado Choco",
      "Boom Boom Choco",
      "Cornetto Choco",
      "Cornetto Cookies & Dream",
      "Bday 3in1 C-K-U",
      "Bday 3in1 U-M-A",
      "Bday 3+1 C-K-U-M",
      "Sup Double Dutch",
      "Sup Rocky Road",
      "Sup Cookies & Cream",
    ];
    final derivedPlaced = placedProductNames ?? [
      for (int i = 0; i < legacyNames.length && i < flags.length; i++)
        if (flags[i]) legacyNames[i]
    ];

    return Placement(
      id: id,
      storeName: storeName,
      deliveryDate: deliveryDate,
      placedProductNames: derivedPlaced,
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
      progressCount: derivedPlaced.length,
    );
  }

  bool isProductPlaced(String productName) {
    final lower = productName.trim().toLowerCase();
    return placedProductNames.any((name) => name.trim().toLowerCase() == lower);
  }

  Placement copyWith({
    String? id,
    String? storeName,
    Timestamp? deliveryDate,
    List<String>? placedProductNames,
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
      placedProductNames: placedProductNames ?? List.from(this.placedProductNames),
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
      'placedProductNames': placedProductNames,
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
