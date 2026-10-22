import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';

// ignore: constant_identifier_names
const String INVENTORY_ALERTS_COLLECTION_REF = 'inventory_alerts';

/// Anomaly alert produced by heuristic and rule-based evaluation of warehouse movements.
class InventoryAlert {
  final String id;
  final String ruleId;
  final String ruleTitle;
  final String severity; // 'info', 'warning', 'high', 'critical'
  final String? productId;
  final String? productName;
  final String? userId;
  final String? userName;
  final String message;
  final List<String> evidenceMovementIds;
  final DateTime detectedAt;
  final String status; // 'open', 'acknowledged'
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final String? acknowledgmentNote;

  const InventoryAlert({
    required this.id,
    required this.ruleId,
    required this.ruleTitle,
    required this.severity,
    this.productId,
    this.productName,
    this.userId,
    this.userName,
    required this.message,
    this.evidenceMovementIds = const [],
    required this.detectedAt,
    this.status = 'open',
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.acknowledgmentNote,
  });

  bool get isOpen => status == 'open';
  bool get isAcknowledged => status == 'acknowledged';

  factory InventoryAlert.fromJson(String id, Map<String, dynamic> json) {
    return InventoryAlert(
      id: id,
      ruleId: json['ruleId'] as String? ?? 'general_anomaly',
      ruleTitle: json['ruleTitle'] as String? ?? 'Inventory Anomaly',
      severity: json['severity'] as String? ?? 'warning',
      productId: json['productId'] as String?,
      productName: json['productName'] as String?,
      userId: json['userId'] as String?,
      userName: json['userName'] as String?,
      message: json['message'] as String? ?? '',
      evidenceMovementIds: (json['evidenceMovementIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      detectedAt: (json['detectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: json['status'] as String? ?? 'open',
      acknowledgedBy: json['acknowledgedBy'] as String?,
      acknowledgedAt: (json['acknowledgedAt'] as Timestamp?)?.toDate(),
      acknowledgmentNote: json['acknowledgmentNote'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'ruleTitle': ruleTitle,
        'severity': severity,
        if (productId != null) 'productId': productId,
        if (productName != null) 'productName': productName,
        if (userId != null) 'userId': userId,
        if (userName != null) 'userName': userName,
        'message': message,
        'evidenceMovementIds': evidenceMovementIds,
        'detectedAt': Timestamp.fromDate(detectedAt),
        'status': status,
        if (acknowledgedBy != null) 'acknowledgedBy': acknowledgedBy,
        if (acknowledgedAt != null) 'acknowledgedAt': Timestamp.fromDate(acknowledgedAt!),
        if (acknowledgmentNote != null) 'acknowledgmentNote': acknowledgmentNote,
      };
}

/// Service that inspects inventory movements and physical product stock to surface
/// suspicious activities, risky patterns, write-off surges, or repeated discrepancies.
class InventoryAlertService {
  final FirebaseFirestore? _customFirestore;
  final InventoryService? _customInventoryService;
  final ConfigurationService? _customConfigService;

  InventoryAlertService({
    FirebaseFirestore? firestore,
    InventoryService? inventoryService,
    ConfigurationService? configService,
  })  : _customFirestore = firestore,
        _customInventoryService = inventoryService,
        _customConfigService = configService;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  InventoryService get _inventoryService => _customInventoryService ?? InventoryService(firestore: _firestore);
  ConfigurationService get _configService => _customConfigService ?? ConfigurationService();

  /// Returns a real-time stream of all open inventory anomaly alerts.
  Stream<List<InventoryAlert>> getOpenAlertsStream() {
    return _firestore
        .collection(INVENTORY_ALERTS_COLLECTION_REF)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snap) => snap.docs.map((d) => InventoryAlert.fromJson(d.id, d.data())).toList());
  }

  /// Evaluates anomaly rules against recent movements and active inventory items.
  /// Generates and deduplicates [InventoryAlert] documents in `inventory_alerts`.
  Future<List<InventoryAlert>> evaluateAnomalies({
    List<InventoryMovement>? movements,
    List<InventoryItem>? items,
    Configuration? config,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final effectiveConfig = config ?? await _configService.getConfiguration();

    // 1. Fetch movements from the last 7 days if not provided
    final List<InventoryMovement> targetMovements;
    if (movements != null) {
      targetMovements = movements;
    } else {
      final sevenDaysAgo = effectiveNow.subtract(const Duration(days: 7));
      targetMovements = await _inventoryService.getMovements(
        limit: 1000,
        startDate: sevenDaysAgo,
      );
    }

    // 2. Fetch inventory items if not provided
    final List<InventoryItem> targetItems;
    if (items != null) {
      targetItems = items;
    } else {
      targetItems = await _inventoryService.getAllInventoryItems();
    }

    final itemMap = {for (final it in targetItems) it.id: it};
    final alerts = <InventoryAlert>[];
    final dateKey = DateFormat('yyyyMMdd').format(effectiveNow);

    // Rule 1: Same user makes > N manual adjustments in 24h
    final twentyFourHoursAgo = effectiveNow.subtract(const Duration(hours: 24));
    final adjustmentsIn24h = targetMovements.where((m) =>
        m.movementType == MovementType.adjustment &&
        m.createdAt.toDate().isAfter(twentyFourHoursAgo)).toList();

    final userAdjustments = <String, List<InventoryMovement>>{};
    for (final m in adjustmentsIn24h) {
      final userKey = m.actorUid ?? m.createdBy;
      if (userKey.isNotEmpty) {
        userAdjustments.putIfAbsent(userKey, () => []).add(m);
      }
    }

    for (final entry in userAdjustments.entries) {
      if (entry.value.length > effectiveConfig.maxAdjustmentsPerUser24h) {
        final sample = entry.value.first;
        final alertId = 'user_adjust_${entry.key}_$dateKey';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'user_frequent_adjustments',
          ruleTitle: 'Frequent User Adjustments',
          severity: 'warning',
          userId: entry.key,
          userName: sample.displayActor,
          message: 'User "${sample.displayActor}" made ${entry.value.length} manual adjustments in 24 hours (threshold: ${effectiveConfig.maxAdjustmentsPerUser24h}).',
          evidenceMovementIds: entry.value.map((m) => m.id).toList(),
          detectedAt: effectiveNow,
        ));
      }
    }

    // Rule 2: Same product adjusted > N times in 7 days
    final productAdjustments = <String, List<InventoryMovement>>{};
    for (final m in targetMovements) {
      if (m.movementType == MovementType.adjustment || m.movementType == MovementType.count_correction) {
        if (m.productId.isNotEmpty) {
          productAdjustments.putIfAbsent(m.productId, () => []).add(m);
        }
      }
    }

    for (final entry in productAdjustments.entries) {
      if (entry.value.length > effectiveConfig.maxAdjustmentsPerProduct7d) {
        final sample = entry.value.first;
        final alertId = 'prod_adjust_${entry.key}_$dateKey';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'product_frequent_adjustments',
          ruleTitle: 'High Product Adjustment Volatility',
          severity: 'warning',
          productId: entry.key,
          productName: sample.productName,
          message: 'Product "${sample.productName}" was adjusted ${entry.value.length} times in the past 7 days (threshold: ${effectiveConfig.maxAdjustmentsPerProduct7d}). Recommend warehouse physical audit.',
          evidenceMovementIds: entry.value.map((m) => m.id).toList(),
          detectedAt: effectiveNow,
        ));
      }
    }

    // Rule 3: Write-off / damage_expiry rate above X% of on-hand or high volume
    final writeOffs = targetMovements.where((m) =>
        m.movementType == MovementType.damage_expiry ||
        m.reasonCode == ReasonCode.damaged ||
        m.reasonCode == ReasonCode.expired).toList();

    final writeOffsByProduct = <String, List<InventoryMovement>>{};
    for (final m in writeOffs) {
      if (m.productId.isNotEmpty) {
        writeOffsByProduct.putIfAbsent(m.productId, () => []).add(m);
      }
    }

    for (final entry in writeOffsByProduct.entries) {
      final totalScrapped = entry.value.fold<int>(0, (acc, m) => acc + m.delta.abs());
      final item = itemMap[entry.key];
      final currentStock = item?.stockQuantity ?? 0;
      final thresholdPercent = effectiveConfig.maxWriteOffPercentage;

      final bool triggersPercent = currentStock > 0 && ((totalScrapped / (currentStock + totalScrapped)) * 100) > thresholdPercent;
      final bool triggersAbsolute = totalScrapped >= 20;

      if (triggersPercent || triggersAbsolute) {
        final sample = entry.value.first;
        final alertId = 'high_scrap_${entry.key}_$dateKey';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'high_write_off_rate',
          ruleTitle: 'High Damage / Write-Off Rate',
          severity: 'high',
          productId: entry.key,
          productName: sample.productName,
          message: 'Product "${sample.productName}" had $totalScrapped units damaged/expired in the past 7 days (Current on-hand: $currentStock).',
          evidenceMovementIds: entry.value.map((m) => m.id).toList(),
          detectedAt: effectiveNow,
        ));
      }
    }

    // Rule 4: Repeated short picks on the same product (> N in 7 days)
    final shortPicks = targetMovements.where((m) =>
        m.movementType == MovementType.pick &&
        (m.shortPickReason != null || m.reason.toLowerCase().contains('short'))).toList();

    final shortPicksByProduct = <String, List<InventoryMovement>>{};
    for (final m in shortPicks) {
      if (m.productId.isNotEmpty) {
        shortPicksByProduct.putIfAbsent(m.productId, () => []).add(m);
      }
    }

    for (final entry in shortPicksByProduct.entries) {
      if (entry.value.length >= effectiveConfig.repeatedShortPickThreshold) {
        final sample = entry.value.first;
        final alertId = 'repeat_short_${entry.key}_$dateKey';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'repeated_short_picks',
          ruleTitle: 'Repeated Short Picks',
          severity: 'high',
          productId: entry.key,
          productName: sample.productName,
          message: 'Product "${sample.productName}" experienced ${entry.value.length} short-picks in the past 7 days. Recorded stock may exceed physical stock.',
          evidenceMovementIds: entry.value.map((m) => m.id).toList(),
          detectedAt: effectiveNow,
        ));
      }
    }

    // Rule 5: Clamped-at-zero events (any occurrence)
    final clampedEvents = targetMovements.where((m) => m.clamped).toList();
    for (final m in clampedEvents) {
      final alertId = 'clamped_${m.id}';
      alerts.add(InventoryAlert(
        id: alertId,
        ruleId: 'clamped_at_zero',
        ruleTitle: 'Stock Clamped At Zero',
        severity: 'critical',
        productId: m.productId,
        productName: m.productName,
        message: 'Deduction for "${m.productName}" was clamped to zero. Requested: ${m.requestedQuantity ?? "unknown"}, previous stock: ${m.previousStock}. Indicates system-physical divergence.',
        evidenceMovementIds: [m.id],
        detectedAt: m.createdAt.toDate(),
      ));
    }

    // Rule 6: Threshold-splitting adjustments (repeated adjustments just below approval threshold)
    final threshold = effectiveConfig.unitApprovalThreshold;
    final nearThresholdAdjustments = targetMovements.where((m) {
      if (m.movementType != MovementType.adjustment) return false;
      final delta = m.delta.abs();
      return delta >= (threshold - 2) && delta <= threshold;
    }).toList();

    final nearThresholdByUser = <String, List<InventoryMovement>>{};
    for (final m in nearThresholdAdjustments) {
      final userKey = m.actorUid ?? m.createdBy;
      if (userKey.isNotEmpty) {
        nearThresholdByUser.putIfAbsent(userKey, () => []).add(m);
      }
    }

    for (final entry in nearThresholdByUser.entries) {
      if (entry.value.length >= 2) {
        final sample = entry.value.first;
        final alertId = 'thresh_split_${entry.key}_$dateKey';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'threshold_splitting',
          ruleTitle: 'Suspected Threshold Splitting',
          severity: 'high',
          userId: entry.key,
          userName: sample.displayActor,
          message: 'User "${sample.displayActor}" made ${entry.value.length} manual adjustments right at the approval limit ($threshold units) within 7 days.',
          evidenceMovementIds: entry.value.map((m) => m.id).toList(),
          detectedAt: effectiveNow,
        ));
      }
    }

    // Rule 7: Quarantined customer returns older than 3 days without inspection
    final quarantined = targetMovements.where((m) =>
        m.movementType == MovementType.customer_return &&
        m.disposition == ReturnDisposition.quarantine).toList();

    for (final q in quarantined) {
      final age = effectiveNow.difference(q.createdAt.toDate());
      if (age.inDays >= 3) {
        final alertId = 'quarantine_aging_${q.id}';
        alerts.add(InventoryAlert(
          id: alertId,
          ruleId: 'quarantine_aging',
          ruleTitle: 'Aged Quarantine Inspection',
          severity: 'medium',
          productId: q.productId,
          productName: q.productName,
          message: 'Quarantined return for "${q.productName}" has been pending dealer inspection for ${age.inDays} days.',
          evidenceMovementIds: [q.id],
          detectedAt: effectiveNow,
        ));
      }
    }

    // 3. Persist alerts to Firestore with deduplication
    for (final alert in alerts) {
      try {
        final docRef = _firestore.collection(INVENTORY_ALERTS_COLLECTION_REF).doc(alert.id);
        final snap = await docRef.get();
        if (!snap.exists) {
          await docRef.set(alert.toJson());
        }
      } catch (e) {
        debugPrint('Error saving inventory alert ${alert.id}: $e');
      }
    }

    return alerts;
  }

  /// Fetches all active open alerts sorted by detectedAt descending.
  Future<List<InventoryAlert>> getOpenAlerts() async {
    try {
      final snap = await _firestore
          .collection(INVENTORY_ALERTS_COLLECTION_REF)
          .where('status', isEqualTo: 'open')
          .get();
      final list = snap.docs.map((doc) => InventoryAlert.fromJson(doc.id, doc.data())).toList();
      list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
      return list;
    } catch (e) {
      debugPrint('getOpenAlerts error: $e');
      return [];
    }
  }

  /// Acknowledges an alert with notes and reviewer credentials.
  Future<void> acknowledgeAlert({
    required String alertId,
    String? note,
    String? notes,
    String? dealerName,
    String? dealerUid,
  }) async {
    final effectiveNote = (notes ?? note ?? '').trim();
    String effectiveDealer = dealerName ?? '';
    if (effectiveDealer.isEmpty) {
      final user = await KVariables.getUser();
      effectiveDealer = (user != null && user.username.isNotEmpty) ? user.username : 'Dealer';
    }
    await _firestore.collection(INVENTORY_ALERTS_COLLECTION_REF).doc(alertId).update({
      'status': 'acknowledged',
      'acknowledgedBy': effectiveDealer,
      'acknowledgedAt': FieldValue.serverTimestamp(),
      'acknowledgmentNote': effectiveNote,
    });
  }

  /// Fetches the count of active open alerts.
  Future<int> getOpenAlertsCount() async {
    try {
      final snap = await _firestore
          .collection(INVENTORY_ALERTS_COLLECTION_REF)
          .where('status', isEqualTo: 'open')
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }
}
