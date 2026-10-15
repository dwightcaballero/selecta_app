import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';

int _parseInt(dynamic val, [int fallback = 0]) {
  if (val == null) return fallback;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val.trim()) ?? fallback;
  return fallback;
}

double _parseDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim()) ?? fallback;
  return fallback;
}

bool _parseBool(dynamic val, [bool fallback = false]) {
  if (val == null) return fallback;
  if (val is bool) return val;
  if (val is num) return val != 0;
  if (val is String) {
    final lower = val.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

Timestamp? _parseTimestamp(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val;
  if (val is DateTime) return Timestamp.fromDate(val);
  if (val is String) {
    final dt = DateTime.tryParse(val.trim());
    if (dt != null) return Timestamp.fromDate(dt);
  }
  return null;
}

/// Represents an item loaded onto the van.
class VanLoadItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String barcode;
  final String productSource; // 'selecta' | 'other'
  final String category;
  final String tag;
  final double buyingPrice;
  final double sellingPrice; // Catalog SRP
  final int loadedQuantity;
  final int soldQuantity;
  final int returnedQuantity;

  const VanLoadItem({
    required this.productId,
    required this.productName,
    this.imageUrl = '',
    this.barcode = '',
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    this.buyingPrice = 0.0,
    required this.sellingPrice,
    required this.loadedQuantity,
    this.soldQuantity = 0,
    this.returnedQuantity = 0,
  });

  /// Quantity currently available on the van for sales.
  int get availableQuantity => (loadedQuantity - soldQuantity).clamp(0, loadedQuantity);

  /// Remaining quantity at end of day (available minus returned).
  int get remainingQuantity => (loadedQuantity - soldQuantity - returnedQuantity).clamp(0, loadedQuantity);

  /// Total value loaded at SRP.
  double get lineTotalLoaded => loadedQuantity * sellingPrice;

  /// Total value sold at SRP.
  double get lineTotalSold => soldQuantity * sellingPrice;

  /// Total value returned at SRP.
  double get lineTotalReturned => returnedQuantity * sellingPrice;

  VanLoadItem copyWith({
    String? productId,
    String? productName,
    String? imageUrl,
    String? barcode,
    String? productSource,
    String? category,
    String? tag,
    double? buyingPrice,
    double? sellingPrice,
    int? loadedQuantity,
    int? soldQuantity,
    int? returnedQuantity,
  }) {
    return VanLoadItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      productSource: productSource ?? this.productSource,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      loadedQuantity: loadedQuantity ?? this.loadedQuantity,
      soldQuantity: soldQuantity ?? this.soldQuantity,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
    );
  }

  factory VanLoadItem.fromJson(Map<String, dynamic> json) {
    return VanLoadItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      category: json['category'] as String? ?? '',
      tag: json['tag'] as String? ?? '',
      buyingPrice: _parseDouble(json['buyingPrice']),
      sellingPrice: _parseDouble(json['sellingPrice']),
      loadedQuantity: _parseInt(json['loadedQuantity']),
      soldQuantity: _parseInt(json['soldQuantity']),
      returnedQuantity: _parseInt(json['returnedQuantity']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'imageUrl': imageUrl,
      'barcode': barcode,
      'productSource': productSource,
      'category': category,
      'tag': tag,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'loadedQuantity': loadedQuantity,
      'soldQuantity': soldQuantity,
      'returnedQuantity': returnedQuantity,
    };
  }
}

/// Represents a daily Van Load manifest for van selling.
class VanLoad {
  String? id;
  Timestamp date;
  String status; // 'draft' | 'loaded' | 'in-route' | 'completed'
  List<VanLoadItem> items;
  String remarks;
  double totalLoadedAmount;
  double totalSoldAmount;
  double totalReturnedAmount;
  bool isStockDeducted;
  bool isStockSettled;
  Timestamp createdDate;
  String createdBy;
  Timestamp lastUpdatedDate;
  String lastUpdatedBy;
  Timestamp? completedDate;
  String? completedBy;

  VanLoad({
    this.id,
    required this.date,
    this.status = VanLoadStatus.draft,
    this.items = const [],
    this.remarks = '',
    this.totalLoadedAmount = 0.0,
    this.totalSoldAmount = 0.0,
    this.totalReturnedAmount = 0.0,
    this.isStockDeducted = false,
    this.isStockSettled = false,
    required this.createdDate,
    required this.createdBy,
    required this.lastUpdatedDate,
    required this.lastUpdatedBy,
    this.completedDate,
    this.completedBy,
  });

  /// Total units loaded across all products.
  int get totalLoadedUnits => items.fold<int>(0, (acc, i) => acc + i.loadedQuantity);

  /// Total units sold across all products.
  int get totalSoldUnits => items.fold<int>(0, (acc, i) => acc + i.soldQuantity);

  /// Total units currently available on the van.
  int get totalAvailableUnits => items.fold<int>(0, (acc, i) => acc + i.availableQuantity);

  /// Total units returned to warehouse.
  int get totalReturnedUnits => items.fold<int>(0, (acc, i) => acc + i.returnedQuantity);

  /// Calculated loaded total value.
  double get calculatedLoadedAmount => items.fold<double>(0.0, (acc, i) => acc + i.lineTotalLoaded);

  /// Calculated sold total value.
  double get calculatedSoldAmount => items.fold<double>(0.0, (acc, i) => acc + i.lineTotalSold);

  /// Calculated returned total value.
  double get calculatedReturnedAmount => items.fold<double>(0.0, (acc, i) => acc + i.lineTotalReturned);

  /// True if the van load is actively usable for selling.
  bool get isActive => status == VanLoadStatus.loaded || status == VanLoadStatus.inRoute;

  /// True if completed/settled for the day.
  bool get isCompleted => status == VanLoadStatus.completed;

  static List<VanLoadItem> _parseItems(Object? raw) {
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => VanLoadItem.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) {
        final catComp = Helperfunctions.compareCategoryHierarchy(a.category, b.category);
        if (catComp != 0) return catComp;
        return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
      });
      return list;
    }
    return const [];
  }

  factory VanLoad.fromJson(Map<String, Object?> json, [String? docId]) {
    return VanLoad(
      id: docId ?? json['id'] as String?,
      date: _parseTimestamp(json['date']) ?? Timestamp.now(),
      status: json['status'] as String? ?? VanLoadStatus.draft,
      items: _parseItems(json['items']),
      remarks: json['remarks'] as String? ?? '',
      totalLoadedAmount: _parseDouble(json['totalLoadedAmount']),
      totalSoldAmount: _parseDouble(json['totalSoldAmount']),
      totalReturnedAmount: _parseDouble(json['totalReturnedAmount']),
      isStockDeducted: _parseBool(json['isStockDeducted']),
      isStockSettled: _parseBool(json['isStockSettled']),
      createdDate: _parseTimestamp(json['createdDate']) ?? Timestamp.now(),
      createdBy: json['createdBy'] as String? ?? '',
      lastUpdatedDate: _parseTimestamp(json['lastUpdatedDate']) ?? Timestamp.now(),
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      completedDate: _parseTimestamp(json['completedDate']),
      completedBy: json['completedBy'] as String?,
    );
  }

  factory VanLoad.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.data() != null) {
      return VanLoad.fromJson(snapshot.data()!, snapshot.id);
    }
    return VanLoad.empty();
  }

  static VanLoad empty() => VanLoad(
    id: null,
    date: Timestamp.now(),
    status: VanLoadStatus.draft,
    items: const [],
    remarks: '',
    totalLoadedAmount: 0.0,
    totalSoldAmount: 0.0,
    totalReturnedAmount: 0.0,
    isStockDeducted: false,
    isStockSettled: false,
    createdDate: Timestamp.now(),
    createdBy: '',
    lastUpdatedDate: Timestamp.now(),
    lastUpdatedBy: '',
    completedDate: null,
    completedBy: null,
  );

  VanLoad copyWith({
    String? id,
    Timestamp? date,
    String? status,
    List<VanLoadItem>? items,
    String? remarks,
    double? totalLoadedAmount,
    double? totalSoldAmount,
    double? totalReturnedAmount,
    bool? isStockDeducted,
    bool? isStockSettled,
    Timestamp? createdDate,
    String? createdBy,
    Timestamp? lastUpdatedDate,
    String? lastUpdatedBy,
    Timestamp? completedDate,
    String? completedBy,
  }) {
    return VanLoad(
      id: id ?? this.id,
      date: date ?? this.date,
      status: status ?? this.status,
      items: items ?? this.items,
      remarks: remarks ?? this.remarks,
      totalLoadedAmount: totalLoadedAmount ?? this.totalLoadedAmount,
      totalSoldAmount: totalSoldAmount ?? this.totalSoldAmount,
      totalReturnedAmount: totalReturnedAmount ?? this.totalReturnedAmount,
      isStockDeducted: isStockDeducted ?? this.isStockDeducted,
      isStockSettled: isStockSettled ?? this.isStockSettled,
      createdDate: createdDate ?? this.createdDate,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedDate: lastUpdatedDate ?? this.lastUpdatedDate,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      completedDate: completedDate ?? this.completedDate,
      completedBy: completedBy ?? this.completedBy,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'date': date,
      'status': status,
      'items': items.map((e) => e.toJson()).toList(),
      'remarks': remarks,
      'totalLoadedAmount': totalLoadedAmount,
      'totalSoldAmount': totalSoldAmount,
      'totalReturnedAmount': totalReturnedAmount,
      'isStockDeducted': isStockDeducted,
      'isStockSettled': isStockSettled,
      'createdDate': createdDate,
      'createdBy': createdBy,
      'lastUpdatedDate': lastUpdatedDate,
      'lastUpdatedBy': lastUpdatedBy,
      'completedDate': completedDate,
      'completedBy': completedBy,
    };
  }
}

class VanLoadModelString {
  static const String date = 'date';
  static const String status = 'status';
  static const String items = 'items';
  static const String remarks = 'remarks';
  static const String totalLoadedAmount = 'totalLoadedAmount';
  static const String totalSoldAmount = 'totalSoldAmount';
  static const String totalReturnedAmount = 'totalReturnedAmount';
  static const String isStockDeducted = 'isStockDeducted';
  static const String isStockSettled = 'isStockSettled';
  static const String createdDate = 'createdDate';
  static const String createdBy = 'createdBy';
  static const String lastUpdatedDate = 'lastUpdatedDate';
  static const String lastUpdatedBy = 'lastUpdatedBy';
  static const String completedDate = 'completedDate';
  static const String completedBy = 'completedBy';
}
