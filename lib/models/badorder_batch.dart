import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

class BadOrderBatch {
  final String id;
  final String batchNumber;
  final String supplierRefNo;
  final Timestamp pulloutDate;
  final List<String> badOrderIds;
  final List<String> storeNames;
  final double totalBatchAmount; // Expected supplier refund (or legacy store total for old batches)
  final double? totalStoreRefundAmount; // Informational: sum of store refunds across all included B.O.s
  final String pricingBasis; // 'supplier_buying_v1' for new batches, 'store_selling_legacy' for old batches
  final int totalItemsCount;
  final String status;
  final String notes;

  // Supplier Refund (Credit Memo) details
  final bool isSupplierRefunded;
  final String supplierCreditMemoNo;
  final Timestamp? supplierRefundDate;
  final double? supplierRefundAmount;
  final String adjustmentReason;
  final String? supplierRefundBy;

  // Audit trails
  final String createdBy;
  final Timestamp createdDate;
  final String lastUpdatedBy;
  final Timestamp lastupdatedDate;

  const BadOrderBatch({
    this.id = '',
    required this.batchNumber,
    required this.supplierRefNo,
    required this.pulloutDate,
    required this.badOrderIds,
    this.storeNames = const [],
    required this.totalBatchAmount,
    this.totalStoreRefundAmount,
    this.pricingBasis = 'supplier_buying_v1',
    this.totalItemsCount = 0,
    this.status = BadOrderStatus.warehousePullout,
    this.notes = '',
    this.isSupplierRefunded = false,
    this.supplierCreditMemoNo = '',
    this.supplierRefundDate,
    this.supplierRefundAmount,
    this.adjustmentReason = '',
    this.supplierRefundBy,
    required this.createdBy,
    required this.createdDate,
    required this.lastUpdatedBy,
    required this.lastupdatedDate,
  });

  bool get isSettled => status == BadOrderStatus.settled || isSupplierRefunded;

  /// True when batch was created under the legacy pricing basis (where batch amount = store selling total).
  bool get isLegacyBasis => pricingBasis != 'supplier_buying_v1';

  /// Variance between what the dealer submitted vs what the supplier actually credited.
  double get varianceAmount => (supplierRefundAmount ?? totalBatchAmount) - totalBatchAmount;

  factory BadOrderBatch.fromJson(Map<String, dynamic> json, [String docId = '']) {
    return BadOrderBatch(
      id: docId.isNotEmpty ? docId : (json['id'] as String? ?? ''),
      batchNumber: json['batchNumber'] as String? ?? '',
      supplierRefNo: json['supplierRefNo'] as String? ?? '',
      pulloutDate: json['pulloutDate'] as Timestamp? ?? Timestamp.now(),
      badOrderIds: (json['badOrderIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      storeNames: (json['storeNames'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      totalBatchAmount: (json['totalBatchAmount'] as num?)?.toDouble() ?? 0.0,
      totalStoreRefundAmount: (json['totalStoreRefundAmount'] as num?)?.toDouble(),
      pricingBasis: json['pricingBasis'] as String? ?? 'store_selling_legacy',
      totalItemsCount: (json['totalItemsCount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? BadOrderStatus.warehousePullout,
      notes: json['notes'] as String? ?? '',
      isSupplierRefunded: json['isSupplierRefunded'] as bool? ?? false,
      supplierCreditMemoNo: json['supplierCreditMemoNo'] as String? ?? '',
      supplierRefundDate: json['supplierRefundDate'] as Timestamp?,
      supplierRefundAmount: (json['supplierRefundAmount'] as num?)?.toDouble(),
      adjustmentReason: json['adjustmentReason'] as String? ?? '',
      supplierRefundBy: json['supplierRefundBy'] as String?,
      createdBy: json['createdBy'] as String? ?? '',
      createdDate: json['createdDate'] as Timestamp? ?? Timestamp.now(),
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      lastupdatedDate: json['lastupdatedDate'] as Timestamp? ?? Timestamp.now(),
    );
  }

  factory BadOrderBatch.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.data() != null) {
      return BadOrderBatch.fromJson(snapshot.data()!, snapshot.id);
    }
    return BadOrderBatch(
      batchNumber: '',
      supplierRefNo: '',
      pulloutDate: Timestamp.now(),
      badOrderIds: const [],
      totalBatchAmount: 0.0,
      createdBy: '',
      createdDate: Timestamp.now(),
      lastUpdatedBy: '',
      lastupdatedDate: Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'batchNumber': batchNumber,
      'supplierRefNo': supplierRefNo,
      'pulloutDate': pulloutDate,
      'badOrderIds': badOrderIds,
      'storeNames': storeNames,
      'totalBatchAmount': totalBatchAmount,
      if (totalStoreRefundAmount != null) 'totalStoreRefundAmount': totalStoreRefundAmount,
      'pricingBasis': pricingBasis,
      'totalItemsCount': totalItemsCount,
      'status': status,
      'notes': notes,
      'isSupplierRefunded': isSupplierRefunded,
      'supplierCreditMemoNo': supplierCreditMemoNo,
      if (supplierRefundDate != null) 'supplierRefundDate': supplierRefundDate,
      if (supplierRefundAmount != null) 'supplierRefundAmount': supplierRefundAmount,
      'adjustmentReason': adjustmentReason,
      if (supplierRefundBy != null) 'supplierRefundBy': supplierRefundBy,
      'createdBy': createdBy,
      'createdDate': createdDate,
      'lastUpdatedBy': lastUpdatedBy,
      'lastupdatedDate': lastupdatedDate,
    };
  }

  BadOrderBatch copyWith({
    String? id,
    String? batchNumber,
    String? supplierRefNo,
    Timestamp? pulloutDate,
    List<String>? badOrderIds,
    List<String>? storeNames,
    double? totalBatchAmount,
    double? totalStoreRefundAmount,
    String? pricingBasis,
    int? totalItemsCount,
    String? status,
    String? notes,
    bool? isSupplierRefunded,
    String? supplierCreditMemoNo,
    Timestamp? supplierRefundDate,
    double? supplierRefundAmount,
    String? adjustmentReason,
    String? supplierRefundBy,
    String? createdBy,
    Timestamp? createdDate,
    String? lastUpdatedBy,
    Timestamp? lastupdatedDate,
  }) {
    return BadOrderBatch(
      id: id ?? this.id,
      batchNumber: batchNumber ?? this.batchNumber,
      supplierRefNo: supplierRefNo ?? this.supplierRefNo,
      pulloutDate: pulloutDate ?? this.pulloutDate,
      badOrderIds: badOrderIds ?? this.badOrderIds,
      storeNames: storeNames ?? this.storeNames,
      totalBatchAmount: totalBatchAmount ?? this.totalBatchAmount,
      totalStoreRefundAmount: totalStoreRefundAmount ?? this.totalStoreRefundAmount,
      pricingBasis: pricingBasis ?? this.pricingBasis,
      totalItemsCount: totalItemsCount ?? this.totalItemsCount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      isSupplierRefunded: isSupplierRefunded ?? this.isSupplierRefunded,
      supplierCreditMemoNo: supplierCreditMemoNo ?? this.supplierCreditMemoNo,
      supplierRefundDate: supplierRefundDate ?? this.supplierRefundDate,
      supplierRefundAmount: supplierRefundAmount ?? this.supplierRefundAmount,
      adjustmentReason: adjustmentReason ?? this.adjustmentReason,
      supplierRefundBy: supplierRefundBy ?? this.supplierRefundBy,
      createdBy: createdBy ?? this.createdBy,
      createdDate: createdDate ?? this.createdDate,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
    );
  }
}
