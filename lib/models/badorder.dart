import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

class BadOrderItem {
  final String productId;
  final String productName;
  final String category; // 'By Piece' or 'By Case'
  final int quantity;
  final double pricePerPiece;
  final double subtotal;
  final String imageUrl;

  const BadOrderItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.pricePerPiece,
    required this.subtotal,
    this.imageUrl = '',
  });

  factory BadOrderItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toInt() ?? 0;
    final price = (json['pricePerPiece'] as num?)?.toDouble() ?? 0.0;
    final sub = (json['subtotal'] as num?)?.toDouble() ?? (qty * price);
    return BadOrderItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantity: qty,
      pricePerPiece: price,
      subtotal: sub,
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'category': category,
      'quantity': quantity,
      'pricePerPiece': pricePerPiece,
      'subtotal': subtotal,
      'imageUrl': imageUrl,
    };
  }
}

class BadOrder {
  String id;
  String hapistore;
  Timestamp badorderDate;
  String imagePath;
  String status;
  String notes;
  List<BadOrderItem> items;
  double badorderAmount;
  int schemaVersion;
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;
  String createdPage;
  String lastUpdatedPage;

  BadOrder({
    this.id = '',
    required this.hapistore,
    required this.badorderDate,
    this.imagePath = '',
    this.status = BadOrderStatus.storePullout,
    this.notes = '',
    this.items = const [],
    double? badorderAmount,
    this.schemaVersion = 2,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
    this.createdPage = '',
    this.lastUpdatedPage = '',
  }) : badorderAmount = badorderAmount ??
            items.fold<double>(0.0, (total, item) => total + item.subtotal);

  /// Backwards-compatibility getter for description (maps to notes)
  String get description => notes;
  set description(String val) => notes = val;

  /// Check if this is a new bad order record with itemized entries.
  bool get isNewRecord => items.isNotEmpty || schemaVersion >= 2;

  /// Computes the total amount from items.
  double get totalAmount =>
      items.fold<double>(0.0, (total, item) => total + item.subtotal);

  static BadOrder empty() => BadOrder(
        hapistore: '',
        badorderDate: Timestamp.now(),
        imagePath: '',
        status: BadOrderStatus.storePullout,
        notes: '',
        items: const [],
        badorderAmount: 0.0,
        schemaVersion: 2,
        createdBy: '',
        lastUpdatedBy: '',
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );

  factory BadOrder.fromJson(Map<String, Object?> json, [String docId = '']) {
    final rawItems = json['items'];
    List<BadOrderItem> parsedItems = [];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          parsedItems.add(BadOrderItem.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final rawAmount = (json['badorderAmount'] as num?)?.toDouble();
    final computedAmount = parsedItems.isNotEmpty
        ? parsedItems.fold<double>(0.0, (total, item) => total + item.subtotal)
        : (rawAmount ?? 0.0);

    return BadOrder(
      id: docId.isNotEmpty ? docId : (json['id'] as String? ?? ''),
      hapistore: json['hapistore'] as String? ?? '',
      badorderDate: json['badorderDate'] as Timestamp? ?? Timestamp.now(),
      imagePath: json['imagePath'] as String? ?? json['imageUrl'] as String? ?? '',
      status: json['status'] as String? ?? BadOrderStatus.storePullout,
      notes: json['notes'] as String? ?? json['description'] as String? ?? '',
      items: parsedItems,
      badorderAmount: computedAmount,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? (parsedItems.isNotEmpty ? 2 : 1),
      createdBy: json['createdBy'] as String? ?? '',
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      createdDate: json['createdDate'] as Timestamp? ?? Timestamp.now(),
      lastupdatedDate: json['lastupdatedDate'] as Timestamp? ?? Timestamp.now(),
      createdPage: json['createdPage'] as String? ?? '',
      lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
    );
  }

  factory BadOrder.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      return BadOrder.fromJson(document.data()!, document.id);
    } else {
      return BadOrder.empty();
    }
  }

  BadOrder copyWith({
    String? id,
    String? hapistore,
    Timestamp? badorderDate,
    String? imagePath,
    String? status,
    String? notes,
    List<BadOrderItem>? items,
    double? badorderAmount,
    int? schemaVersion,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    String? createdPage,
    String? lastUpdatedPage,
  }) {
    return BadOrder(
      id: id ?? this.id,
      hapistore: hapistore ?? this.hapistore,
      badorderDate: badorderDate ?? this.badorderDate,
      imagePath: imagePath ?? this.imagePath,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      badorderAmount: badorderAmount ?? this.badorderAmount,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
      createdPage: createdPage ?? this.createdPage,
      lastUpdatedPage: lastUpdatedPage ?? this.lastUpdatedPage,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'hapistore': hapistore,
      'badorderDate': badorderDate,
      'imagePath': imagePath,
      'status': status,
      'notes': notes,
      'description': notes,
      'items': items.map((i) => i.toJson()).toList(),
      'badorderAmount': totalAmount,
      'schemaVersion': schemaVersion,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
    };
  }
}
