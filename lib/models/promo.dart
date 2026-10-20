import 'package:cloud_firestore/cloud_firestore.dart';

int? _parseInt(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val.trim());
  return null;
}

double _parseDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim()) ?? fallback;
  return fallback;
}

double? _parseDoubleNullable(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim());
  return null;
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

/// A single product requirement within a promo rule.
class PromoRule {
  final String productId;
  final String productName;
  final String productSource; // 'selecta' | 'other'
  final int requiredQty;

  const PromoRule({
    required this.productId,
    this.productName = '',
    this.productSource = 'selecta',
    required this.requiredQty,
  });

  PromoRule copyWith({
    String? productId,
    String? productName,
    String? productSource,
    int? requiredQty,
  }) {
    return PromoRule(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSource: productSource ?? this.productSource,
      requiredQty: requiredQty ?? this.requiredQty,
    );
  }

  factory PromoRule.fromJson(Map<String, dynamic> json) {
    return PromoRule(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productSource: json['productSource']?.toString() ?? 'selecta',
      requiredQty: _parseInt(json['requiredQty']) ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'productSource': productSource,
      'requiredQty': requiredQty,
    };
  }
}

/// A free item rewarded when promo criteria are met.
class PromoFreeItem {
  final String productId;
  final String productName;
  final String productSource;
  final String category;
  final int quantity;
  final double buyingPrice;
  final String imageUrl;

  const PromoFreeItem({
    required this.productId,
    required this.productName,
    this.productSource = 'selecta',
    this.category = 'By Piece',
    required this.quantity,
    this.buyingPrice = 0.0,
    this.imageUrl = '',
  });

  PromoFreeItem copyWith({
    String? productId,
    String? productName,
    String? productSource,
    String? category,
    int? quantity,
    double? buyingPrice,
    String? imageUrl,
  }) {
    return PromoFreeItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSource: productSource ?? this.productSource,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory PromoFreeItem.fromJson(Map<String, dynamic> json) {
    return PromoFreeItem(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productSource: json['productSource']?.toString() ?? 'selecta',
      category: json['category']?.toString() ?? 'By Piece',
      quantity: _parseInt(json['quantity']) ?? 1,
      buyingPrice: _parseDouble(json['buyingPrice']),
      imageUrl: json['imageUrl']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'productSource': productSource,
      'category': category,
      'quantity': quantity,
      'buyingPrice': buyingPrice,
      'imageUrl': imageUrl,
    };
  }
}

/// The reward definition of a promotion.
class PromoReward {
  final String type; // 'fixed' | 'percent' | 'freeItem'
  final double? amount; // for 'fixed' (PHP off)
  final double? percent; // for 'percent' (e.g. 10.0 for 10% off)
  final List<PromoFreeItem> freeItems;

  const PromoReward({
    required this.type,
    this.amount,
    this.percent,
    this.freeItems = const [],
  });

  bool get isFreeReward => type == 'freeItem' || type == 'free_item';
  bool get isPercentage => type == 'percent' || type == 'percentage';
  bool get isFixed => type == 'fixed';

  PromoReward copyWith({
    String? type,
    double? amount,
    double? percent,
    List<PromoFreeItem>? freeItems,
  }) {
    return PromoReward(
      type: type ?? this.type,
      amount: amount ?? this.amount,
      percent: percent ?? this.percent,
      freeItems: freeItems ?? this.freeItems,
    );
  }

  factory PromoReward.fromJson(Map<String, dynamic> json) {
    return PromoReward(
      type: json['type']?.toString() ?? 'fixed',
      amount: _parseDoubleNullable(json['amount']),
      percent: _parseDoubleNullable(json['percent']),
      freeItems: (json['freeItems'] as List<dynamic>?)
              ?.map((item) => PromoFreeItem.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'amount': amount,
      'percent': percent,
      'freeItems': freeItems.map((f) => f.toJson()).toList(),
    };
  }
}

/// A master promotion definition.
class Promo {
  final String id;
  final String name;
  final String description;
  final bool isActive;
  final Timestamp? startDate;
  final Timestamp? endDate;
  final int priority; // higher priority evaluated first
  final List<PromoRule> rules;
  final PromoReward reward;
  final bool repeatPerSet;
  final int? maxApplicationsPerOrder;
  final int? limitPerStore; // null = unlimited, 1 = once per store, N = N times
  final String fundedBy; // 'dealer' | 'supplier'
  final String? supplierName;
  final bool supplierRefundable;
  final String createdBy;
  final Timestamp createdDate;
  final Timestamp lastUpdatedDate;

  const Promo({
    required this.id,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.startDate,
    this.endDate,
    this.priority = 0,
    required this.rules,
    required this.reward,
    this.repeatPerSet = true,
    this.maxApplicationsPerOrder,
    this.limitPerStore,
    this.fundedBy = 'dealer',
    this.supplierName,
    this.supplierRefundable = false,
    this.createdBy = '',
    required this.createdDate,
    required this.lastUpdatedDate,
  });

  /// Returns true if currently active and within valid date window.
  bool isValidAt(DateTime date) {
    if (!isActive) return false;
    if (startDate != null && date.isBefore(startDate!.toDate())) return false;
    if (endDate != null && date.isAfter(endDate!.toDate())) return false;
    return true;
  }

  Promo copyWith({
    String? id,
    String? name,
    String? description,
    bool? isActive,
    Timestamp? startDate,
    Timestamp? endDate,
    int? priority,
    List<PromoRule>? rules,
    PromoReward? reward,
    bool? repeatPerSet,
    int? maxApplicationsPerOrder,
    int? limitPerStore,
    String? fundedBy,
    String? supplierName,
    bool? supplierRefundable,
    String? createdBy,
    Timestamp? createdDate,
    Timestamp? lastUpdatedDate,
  }) {
    return Promo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      priority: priority ?? this.priority,
      rules: rules ?? this.rules,
      reward: reward ?? this.reward,
      repeatPerSet: repeatPerSet ?? this.repeatPerSet,
      maxApplicationsPerOrder: maxApplicationsPerOrder ?? this.maxApplicationsPerOrder,
      limitPerStore: limitPerStore ?? this.limitPerStore,
      fundedBy: fundedBy ?? this.fundedBy,
      supplierName: supplierName ?? this.supplierName,
      supplierRefundable: supplierRefundable ?? this.supplierRefundable,
      createdBy: createdBy ?? this.createdBy,
      createdDate: createdDate ?? this.createdDate,
      lastUpdatedDate: lastUpdatedDate ?? this.lastUpdatedDate,
    );
  }

  factory Promo.fromJson(Map<String, dynamic> json, [String? docId]) {
    return Promo(
      id: docId ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isActive: _parseBool(json['isActive'], true),
      startDate: _parseTimestamp(json['startDate']),
      endDate: _parseTimestamp(json['endDate']),
      priority: _parseInt(json['priority']) ?? 0,
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => PromoRule.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList() ??
          const [],
      reward: json['reward'] != null
          ? PromoReward.fromJson(Map<String, dynamic>.from(json['reward'] as Map))
          : const PromoReward(type: 'fixed', amount: 0.0),
      repeatPerSet: _parseBool(json['repeatPerSet'], true),
      maxApplicationsPerOrder: _parseInt(json['maxApplicationsPerOrder']),
      limitPerStore: _parseInt(json['limitPerStore']),
      fundedBy: json['fundedBy']?.toString() ?? 'dealer',
      supplierName: json['supplierName']?.toString(),
      supplierRefundable: _parseBool(json['supplierRefundable'], false),
      createdBy: json['createdBy']?.toString() ?? '',
      createdDate: _parseTimestamp(json['createdDate']) ?? Timestamp.now(),
      lastUpdatedDate: _parseTimestamp(json['lastUpdatedDate']) ?? Timestamp.now(),
    );
  }

  factory Promo.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Promo.fromJson(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'isActive': isActive,
      'startDate': startDate,
      'endDate': endDate,
      'priority': priority,
      'rules': rules.map((r) => r.toJson()).toList(),
      'reward': reward.toJson(),
      'repeatPerSet': repeatPerSet,
      'maxApplicationsPerOrder': maxApplicationsPerOrder,
      'limitPerStore': limitPerStore,
      'fundedBy': fundedBy,
      'supplierName': supplierName,
      'supplierRefundable': supplierRefundable,
      'createdBy': createdBy,
      'createdDate': createdDate,
      'lastUpdatedDate': lastUpdatedDate,
    };
  }
}

/// An immutable snapshot of an applied promo attached to a Delivery order.
class AppliedPromo {
  final String promoId;
  final String name;
  final int timesApplied;
  final double discountAmount;
  final String fundedBy;
  final String? supplierName;
  final bool supplierRefundable;
  final List<PromoRule> rules;
  final PromoReward reward;
  final List<String> freeItemProductIds;

  const AppliedPromo({
    required this.promoId,
    required this.name,
    required this.timesApplied,
    required this.discountAmount,
    this.fundedBy = 'dealer',
    this.supplierName,
    this.supplierRefundable = false,
    this.rules = const [],
    required this.reward,
    this.freeItemProductIds = const [],
  });

  /// Alias for [name] for backward/convenience compatibility.
  String get promoTitle => name;

  AppliedPromo copyWith({
    String? promoId,
    String? name,
    int? timesApplied,
    double? discountAmount,
    String? fundedBy,
    String? supplierName,
    bool? supplierRefundable,
    List<PromoRule>? rules,
    PromoReward? reward,
    List<String>? freeItemProductIds,
  }) {
    return AppliedPromo(
      promoId: promoId ?? this.promoId,
      name: name ?? this.name,
      timesApplied: timesApplied ?? this.timesApplied,
      discountAmount: discountAmount ?? this.discountAmount,
      fundedBy: fundedBy ?? this.fundedBy,
      supplierName: supplierName ?? this.supplierName,
      supplierRefundable: supplierRefundable ?? this.supplierRefundable,
      rules: rules ?? this.rules,
      reward: reward ?? this.reward,
      freeItemProductIds: freeItemProductIds ?? this.freeItemProductIds,
    );
  }

  factory AppliedPromo.fromJson(Map<String, dynamic> json) {
    return AppliedPromo(
      promoId: json['promoId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      timesApplied: _parseInt(json['timesApplied']) ?? 1,
      discountAmount: _parseDouble(json['discountAmount']),
      fundedBy: json['fundedBy']?.toString() ?? 'dealer',
      supplierName: json['supplierName']?.toString(),
      supplierRefundable: _parseBool(json['supplierRefundable'], false),
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => PromoRule.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList() ??
          const [],
      reward: json['reward'] != null
          ? PromoReward.fromJson(Map<String, dynamic>.from(json['reward'] as Map))
          : const PromoReward(type: 'fixed', amount: 0.0),
      freeItemProductIds: (json['freeItemProductIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'promoId': promoId,
      'name': name,
      'timesApplied': timesApplied,
      'discountAmount': discountAmount,
      'fundedBy': fundedBy,
      'supplierName': supplierName,
      'supplierRefundable': supplierRefundable,
      'rules': rules.map((r) => r.toJson()).toList(),
      'reward': reward.toJson(),
      'freeItemProductIds': freeItemProductIds,
    };
  }
}
