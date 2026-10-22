import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/inventory_movement.dart';

/// Represents a manual stock adjustment that exceeds the unit approval threshold
/// and requires dealer authorization before being committed to inventory.
class InventoryPendingAdjustment {
  final String id;
  final String productId;
  final String productName;
  final String productSource; // 'selecta' | 'other'
  final int previousStock;
  final int requestedStock;
  final int delta;
  final String reason;
  final String notes;
  final ReasonCode? reasonCode;
  final String requestedByUid;
  final String requestedByName;
  final DateTime requestedAt;
  final String status; // 'pending', 'approved', 'rejected'
  final String? reviewedByUid;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  const InventoryPendingAdjustment({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSource,
    required this.previousStock,
    required this.requestedStock,
    required this.delta,
    required this.reason,
    this.notes = '',
    this.reasonCode,
    required this.requestedByUid,
    required this.requestedByName,
    required this.requestedAt,
    this.status = 'pending',
    this.reviewedByUid,
    this.reviewedByName,
    this.reviewedAt,
    this.rejectionReason,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory InventoryPendingAdjustment.fromJson(String id, Map<String, dynamic> json) {
    return InventoryPendingAdjustment(
      id: id,
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      previousStock: (json['previousStock'] as num?)?.toInt() ?? 0,
      requestedStock: (json['requestedStock'] as num?)?.toInt() ?? 0,
      delta: (json['delta'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? 'Manual Adjustment',
      notes: json['notes'] as String? ?? '',
      reasonCode: ReasonCode.fromKey(json['reasonCode'] as String?),
      requestedByUid: json['requestedByUid'] as String? ?? '',
      requestedByName: json['requestedByName'] as String? ?? 'Dealer',
      requestedAt: (json['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: json['status'] as String? ?? 'pending',
      reviewedByUid: json['reviewedByUid'] as String?,
      reviewedByName: json['reviewedByName'] as String?,
      reviewedAt: (json['reviewedAt'] as Timestamp?)?.toDate(),
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'productSource': productSource,
        'previousStock': previousStock,
        'requestedStock': requestedStock,
        'delta': delta,
        'reason': reason,
        'notes': notes,
        if (reasonCode != null) 'reasonCode': reasonCode!.key,
        'requestedByUid': requestedByUid,
        'requestedByName': requestedByName,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'status': status,
        if (reviewedByUid != null) 'reviewedByUid': reviewedByUid,
        if (reviewedByName != null) 'reviewedByName': reviewedByName,
        if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
      };
}
