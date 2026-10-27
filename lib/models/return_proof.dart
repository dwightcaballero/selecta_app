import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

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

/// Snapshot of an item returned by a store under a delivery order.
class ReturnProofItem {
  final String deliveryId;
  final String productId;
  final String productName;
  final int returnedQuantity;
  final int receivedQuantity;
  final double sellingPrice;
  final String category;
  final String productSource;

  const ReturnProofItem({
    required this.deliveryId,
    required this.productId,
    required this.productName,
    required this.returnedQuantity,
    int? receivedQuantity,
    this.sellingPrice = 0.0,
    this.category = '',
    this.productSource = 'selecta',
  }) : receivedQuantity = receivedQuantity ?? returnedQuantity;

  bool get hasVariance => receivedQuantity != returnedQuantity;
  int get variance => receivedQuantity - returnedQuantity;

  ReturnProofItem copyWith({
    String? deliveryId,
    String? productId,
    String? productName,
    int? returnedQuantity,
    int? receivedQuantity,
    double? sellingPrice,
    String? category,
    String? productSource,
  }) {
    return ReturnProofItem(
      deliveryId: deliveryId ?? this.deliveryId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      category: category ?? this.category,
      productSource: productSource ?? this.productSource,
    );
  }

  factory ReturnProofItem.fromJson(Map<String, dynamic> json) {
    final retQty = _parseInt(json['returnedQuantity']) ?? 0;
    final recQty = _parseInt(json['receivedQuantity']) ?? retQty;
    return ReturnProofItem(
      deliveryId: json['deliveryId'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      returnedQuantity: retQty,
      receivedQuantity: recQty,
      sellingPrice: _parseDouble(json['sellingPrice']),
      category: json['category'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'deliveryId': deliveryId,
      'productId': productId,
      'productName': productName,
      'returnedQuantity': returnedQuantity,
      'receivedQuantity': receivedQuantity,
      'sellingPrice': sellingPrice,
      'category': category,
      'productSource': productSource,
    };
  }
}

/// Audit trail record for re-submissions, approvals, or rejections.
class ReturnProofHistory {
  final String imageUrl;
  final String notes;
  final String status;
  final String actionBy;
  final Timestamp actionDate;
  final String? rejectReason;

  const ReturnProofHistory({
    required this.imageUrl,
    this.notes = '',
    required this.status,
    required this.actionBy,
    required this.actionDate,
    this.rejectReason,
  });

  factory ReturnProofHistory.fromJson(Map<String, dynamic> json) {
    return ReturnProofHistory(
      imageUrl: json['imageUrl'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? '',
      actionBy: json['actionBy'] as String? ?? '',
      actionDate: _parseTimestamp(json['actionDate']) ?? Timestamp.now(),
      rejectReason: json['rejectReason'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'imageUrl': imageUrl,
      'notes': notes,
      'status': status,
      'actionBy': actionBy,
      'actionDate': actionDate,
      if (rejectReason != null) 'rejectReason': rejectReason,
    };
  }
}

/// Represents the Return Proof for a specific store on a specific business date.
class ReturnProof {
  final String id;
  final String storeName;
  final Timestamp proofDate;
  final String dayKey;
  final List<String> deliveryIds;
  final List<ReturnProofItem> items;
  final String imageUrl;
  final String notes;
  final String status; // 'none' | 'submitted' | 'confirmed' | 'rejected' | 'overridden'
  final String submittedBy;
  final Timestamp? submittedDate;
  final String confirmedBy;
  final Timestamp? confirmedDate;
  final String rejectReason;
  final String overrideBy;
  final Timestamp? overrideDate;
  final String overrideReason;
  final List<ReturnProofHistory> history;
  final Timestamp createdAt;
  final Timestamp lastUpdatedDate;

  ReturnProof({
    this.id = '',
    required this.storeName,
    required this.proofDate,
    required this.dayKey,
    this.deliveryIds = const [],
    this.items = const [],
    this.imageUrl = '',
    this.notes = '',
    this.status = ReturnProofStatus.none,
    this.submittedBy = '',
    this.submittedDate,
    this.confirmedBy = '',
    this.confirmedDate,
    this.rejectReason = '',
    this.overrideBy = '',
    this.overrideDate,
    this.overrideReason = '',
    this.history = const [],
    Timestamp? createdAt,
    Timestamp? lastUpdatedDate,
  })  : createdAt = createdAt ?? Timestamp.now(),
        lastUpdatedDate = lastUpdatedDate ?? Timestamp.now();

  bool get isSatisfied => ReturnProofStatus.isSatisfied(status);
  bool get isConfirmed => status == ReturnProofStatus.confirmed;
  bool get isOverridden => status == ReturnProofStatus.overridden;
  bool get isSubmitted => status == ReturnProofStatus.submitted;
  bool get isRejected => status == ReturnProofStatus.rejected;
  bool get hasVariance => items.any((i) => i.hasVariance);

  int get totalReturnedQuantity =>
      items.fold<int>(0, (acc, item) => acc + item.returnedQuantity);

  int get totalReceivedQuantity =>
      items.fold<int>(0, (acc, item) => acc + item.receivedQuantity);

  static ReturnProof empty() => ReturnProof(
        storeName: '',
        proofDate: Timestamp.now(),
        dayKey: '',
        deliveryIds: const [],
        items: const [],
        imageUrl: '',
        notes: '',
        status: ReturnProofStatus.none,
      );

  factory ReturnProof.fromJson(Map<String, dynamic> json, {String id = ''}) {
    final rawDate = _parseTimestamp(json['proofDate']) ?? Timestamp.now();
    final itemsList = (json['items'] as List<dynamic>?)
            ?.map((e) => ReturnProofItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [];
    final historyList = (json['history'] as List<dynamic>?)
            ?.map((e) => ReturnProofHistory.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [];
    final deliveryIdsList = (json['deliveryIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return ReturnProof(
      id: id.isNotEmpty ? id : (json['id'] as String? ?? '').trim(),
      storeName: (json['storeName'] as String? ?? '').trim(),
      proofDate: rawDate,
      dayKey: (json['dayKey'] as String? ?? '').trim(),
      deliveryIds: deliveryIdsList,
      items: itemsList,
      imageUrl: (json['imageUrl'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? ReturnProofStatus.none).trim(),
      submittedBy: (json['submittedBy'] as String? ?? '').trim(),
      submittedDate: _parseTimestamp(json['submittedDate']),
      confirmedBy: (json['confirmedBy'] as String? ?? '').trim(),
      confirmedDate: _parseTimestamp(json['confirmedDate']),
      rejectReason: (json['rejectReason'] as String? ?? '').trim(),
      overrideBy: (json['overrideBy'] as String? ?? '').trim(),
      overrideDate: _parseTimestamp(json['overrideDate']),
      overrideReason: (json['overrideReason'] as String? ?? '').trim(),
      history: historyList,
      createdAt: _parseTimestamp(json['createdAt']) ?? Timestamp.now(),
      lastUpdatedDate: _parseTimestamp(json['lastUpdatedDate']) ?? Timestamp.now(),
    );
  }

  factory ReturnProof.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data != null) {
      return ReturnProof.fromJson(data, id: snapshot.id);
    }
    return ReturnProof.empty();
  }

  ReturnProof copyWith({
    String? id,
    String? storeName,
    Timestamp? proofDate,
    String? dayKey,
    List<String>? deliveryIds,
    List<ReturnProofItem>? items,
    String? imageUrl,
    String? notes,
    String? status,
    String? submittedBy,
    Timestamp? submittedDate,
    String? confirmedBy,
    Timestamp? confirmedDate,
    String? rejectReason,
    String? overrideBy,
    Timestamp? overrideDate,
    String? overrideReason,
    List<ReturnProofHistory>? history,
    Timestamp? createdAt,
    Timestamp? lastUpdatedDate,
  }) {
    return ReturnProof(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      proofDate: proofDate ?? this.proofDate,
      dayKey: dayKey ?? this.dayKey,
      deliveryIds: deliveryIds ?? this.deliveryIds,
      items: items ?? this.items,
      imageUrl: imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      submittedBy: submittedBy ?? this.submittedBy,
      submittedDate: submittedDate ?? this.submittedDate,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedDate: confirmedDate ?? this.confirmedDate,
      rejectReason: rejectReason ?? this.rejectReason,
      overrideBy: overrideBy ?? this.overrideBy,
      overrideDate: overrideDate ?? this.overrideDate,
      overrideReason: overrideReason ?? this.overrideReason,
      history: history ?? this.history,
      createdAt: createdAt ?? this.createdAt,
      lastUpdatedDate: lastUpdatedDate ?? this.lastUpdatedDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'storeName': storeName,
      'proofDate': proofDate,
      'dayKey': dayKey,
      'deliveryIds': deliveryIds,
      'items': items.map((e) => e.toJson()).toList(),
      'imageUrl': imageUrl,
      'notes': notes,
      'status': status,
      'submittedBy': submittedBy,
      'submittedDate': submittedDate,
      'confirmedBy': confirmedBy,
      'confirmedDate': confirmedDate,
      'rejectReason': rejectReason,
      'overrideBy': overrideBy,
      'overrideDate': overrideDate,
      'overrideReason': overrideReason,
      'history': history.map((e) => e.toJson()).toList(),
      'createdAt': createdAt,
      'lastUpdatedDate': lastUpdatedDate,
    };
  }
}
