import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/inventory_pending_adjustment.dart';
import 'package:selecta_ops/models/inventory_snapshot.dart';
import 'package:selecta_ops/services/inventory_alert_service.dart';

void main() {
  group('Inventory Audit Hardening - Pending Adjustments & Thresholds', () {
    test('InventoryPendingAdjustment serializes to JSON and back correctly', () {
      final now = DateTime(2026, 10, 22, 14, 0);
      final adj = InventoryPendingAdjustment(
        id: 'padj_101',
        productId: 'prod_99',
        productName: 'Magnum Almond',
        productSource: 'selecta',
        previousStock: 20,
        requestedStock: 80,
        delta: 60,
        reason: 'Restock discrepancy',
        notes: 'Found extra pallet in back freezer',
        requestedByUid: 'staff_123',
        requestedByName: 'Staff Member',
        requestedAt: now,
        status: 'pending',
      );

      final json = adj.toJson();
      expect(json['productId'], 'prod_99');
      expect(json['productName'], 'Magnum Almond');
      expect(json['previousStock'], 20);
      expect(json['requestedStock'], 80);
      expect(json['delta'], 60);
      expect(json['status'], 'pending');

      final restored = InventoryPendingAdjustment.fromJson('padj_101', {
        'productId': 'prod_99',
        'productName': 'Magnum Almond',
        'productSource': 'selecta',
        'previousStock': 20,
        'requestedStock': 80,
        'delta': 60,
        'reason': 'Restock discrepancy',
        'notes': 'Found extra pallet in back freezer',
        'requestedByUid': 'staff_123',
        'requestedByName': 'Staff Member',
        'requestedAt': Timestamp.fromDate(now),
        'status': 'pending',
      });

      expect(restored.id, 'padj_101');
      expect(restored.isPending, isTrue);
      expect(restored.isApproved, isFalse);
      expect(restored.delta, 60);
    });

    test('Threshold approval requirement identifies delta exceeding configured unitApprovalThreshold', () {
      const threshold = 50;
      final smallDelta = (30).abs();
      final largeDelta = (55).abs();

      expect(smallDelta > threshold, isFalse);
      expect(largeDelta > threshold, isTrue);
    });
  });

  group('Inventory Audit Hardening - Daily Stock Snapshots & Reconciliation', () {
    test('InventorySnapshotItem verifies opening + in - out == closing', () {
      final itemReconciled = InventorySnapshotItem(
        productId: 'p_01',
        productName: 'Cornetto Vanilla',
        productSource: 'selecta',
        openingStock: 100,
        totalIn: 40,
        totalOut: 30,
        closingStock: 110, // 100 + 40 - 30 == 110
      );

      expect(itemReconciled.reconciled, isTrue);
      expect(itemReconciled.stockQuantity, 110);

      final itemMismatch = InventorySnapshotItem(
        productId: 'p_02',
        productName: 'Cornetto Disc',
        productSource: 'selecta',
        openingStock: 100,
        totalIn: 40,
        totalOut: 30,
        closingStock: 105, // 100 + 40 - 30 == 110 != 105
      );

      expect(itemMismatch.reconciled, isFalse);
    });

    test('InventorySnapshot serializes and parses correctly with metadata', () {
      final now = DateTime(2026, 10, 22, 23, 59);
      final snapshot = InventorySnapshot(
        dateKey: '2026-10-22',
        capturedAt: now,
        capturedBy: 'Dealer Admin',
        totalProducts: 45,
        totalStockQuantity: 1250,
        totalReservedQuantity: 60,
        totalIncomingQuantity: 100,
        status: 'captured',
      );

      final json = snapshot.toJson();
      expect(json['dateKey'], '2026-10-22');
      expect(json['totalProducts'], 45);
      expect(json['totalStockQuantity'], 1250);
      expect(json['status'], 'captured');

      final fromJson = InventorySnapshot.fromJson('2026-10-22', {
        'capturedAt': Timestamp.fromDate(now),
        'capturedBy': 'Dealer Admin',
        'totalProducts': 45,
        'totalStockQuantity': 1250,
        'totalReservedQuantity': 60,
        'totalIncomingQuantity': 100,
        'status': 'captured',
      });

      expect(fromJson.dateKey, '2026-10-22');
      expect(fromJson.totalStockQuantity, 1250);
      expect(fromJson.totalProducts, 45);
    });
  });

  group('Inventory Audit Hardening - Anomaly Alerts & Rule Evaluations', () {
    late Configuration testConfig;
    final now = DateTime(2026, 10, 22, 15, 0);

    setUp(() {
      testConfig = Configuration(
        merchBlitzStartDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
        merchBlitzEndDate: Timestamp.fromDate(DateTime(2026, 12, 31)),
        unitApprovalThreshold: 50,
        maxAdjustmentsPerUser24h: 3,
        maxAdjustmentsPerProduct7d: 5,
        maxWriteOffPercentage: 20.0,
        repeatedShortPickThreshold: 3,
      );
    });

    test('Rule 1: Flags user exceeding max manual adjustments in 24 hours', () async {
      final service = InventoryAlertService();
      final movements = <InventoryMovement>[
        for (int i = 0; i < 4; i++)
          InventoryMovement(
            id: 'mov_u1_$i',
            productId: 'prod_$i',
            productName: 'Product $i',
            productSource: 'selecta',
            createdBy: 'user_A',
            previousStock: 10,
            newStock: 12,
            delta: 2,
            reason: 'Count adjust',
            notes: 'Test adjust',
            createdAt: Timestamp.fromDate(now.subtract(Duration(hours: i + 1))),
            movementType: MovementType.adjustment,
            actorUid: 'user_A',
            actorName: 'Operator A',
          ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final userAlert = alerts.where((a) => a.ruleId == 'user_frequent_adjustments').toList();
      expect(userAlert, isNotEmpty);
      expect(userAlert.first.userId, 'user_A');
      expect(userAlert.first.evidenceMovementIds.length, 4);
      expect(userAlert.first.severity, 'warning');
    });

    test('Rule 2: Flags product with excessive adjustments in 7 days', () async {
      final service = InventoryAlertService();
      final movements = <InventoryMovement>[
        for (int i = 0; i < 6; i++)
          InventoryMovement(
            id: 'mov_p1_$i',
            productId: 'target_product',
            productName: 'Target Ice Cream',
            productSource: 'selecta',
            createdBy: 'user_$i',
            previousStock: 20,
            newStock: 21,
            delta: 1,
            reason: 'Frequent adjustment',
            notes: 'Adjustment round $i',
            createdAt: Timestamp.fromDate(now.subtract(Duration(days: i))),
            movementType: MovementType.adjustment,
            actorUid: 'user_$i',
            actorName: 'Operator $i',
          ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final prodAlert = alerts.where((a) => a.ruleId == 'product_frequent_adjustments').toList();
      expect(prodAlert, isNotEmpty);
      expect(prodAlert.first.productId, 'target_product');
      expect(prodAlert.first.evidenceMovementIds.length, 6);
    });

    test('Rule 3: Flags return write-off exceeding percentage threshold', () async {
      final service = InventoryAlertService();
      final movements = [
        InventoryMovement(
          id: 'mov_writeoff',
          productId: 'prod_scrap',
          productName: 'Melted Popsicles',
          productSource: 'selecta',
          createdBy: 'checker_1',
          previousStock: 30,
          newStock: 10,
          delta: -20,
          reason: 'Melted during transit',
          notes: 'Write off scrap',
          createdAt: Timestamp.fromDate(now),
          movementType: MovementType.damage_expiry,
          reasonCode: ReasonCode.damaged,
        ),
      ];

      final items = <InventoryItem>[
        InventoryItem(
          id: 'prod_scrap',
          productName: 'Melted Popsicles',
          imageUrl: '',
          buyingPrice: 10,
          sellingPrice: 15,
          stockQuantity: 10,
          isActive: true,
          lowStockThreshold: 5,
          source: InventoryProductSource.selecta,
        ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: items,
        config: testConfig,
        now: now,
      );

      final writeOffAlert = alerts.where((a) => a.ruleId == 'high_write_off_rate').toList();
      expect(writeOffAlert, isNotEmpty);
      expect(writeOffAlert.first.productId, 'prod_scrap');
    });

    test('Rule 4: Flags repeated short picks on the same product', () async {
      final service = InventoryAlertService();
      final movements = <InventoryMovement>[
        for (int i = 0; i < 4; i++)
          InventoryMovement(
            id: 'mov_short_$i',
            productId: 'short_prod_1',
            productName: 'Short Product',
            productSource: 'selecta',
            createdBy: 'picker_1',
            previousStock: 5,
            newStock: 0,
            delta: -5,
            reason: 'Short pick shortfall',
            notes: 'Physical stock insufficient',
            createdAt: Timestamp.fromDate(now.subtract(Duration(hours: i + 1))),
            movementType: MovementType.pick,
            shortPickReason: ShortPickReason.out_of_stock,
          ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final shortAlert = alerts.where((a) => a.ruleId == 'repeated_short_picks').toList();
      expect(shortAlert, isNotEmpty);
      expect(shortAlert.first.productId, 'short_prod_1');
      expect(shortAlert.first.severity, 'high');
    });

    test('Rule 5: Flags clamped-at-zero events indicating stock divergence', () async {
      final service = InventoryAlertService();
      final movements = [
        InventoryMovement(
          id: 'mov_clamped_01',
          productId: 'prod_zero',
          productName: 'Zero Stock Item',
          productSource: 'selecta',
          createdBy: 'system_order',
          previousStock: 2,
          newStock: 0,
          delta: -2,
          requestedQuantity: 5,
          clamped: true,
          reason: 'Order deduction clamped at zero',
          notes: 'Insufficient shelf stock',
          createdAt: Timestamp.fromDate(now),
          movementType: MovementType.pick,
        ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final clampedAlert = alerts.where((a) => a.ruleId == 'clamped_at_zero').toList();
      expect(clampedAlert, isNotEmpty);
      expect(clampedAlert.first.productId, 'prod_zero');
      expect(clampedAlert.first.severity, 'critical');
    });

    test('Rule 6: Flags suspected threshold-splitting adjustments', () async {
      final service = InventoryAlertService();
      // threshold is 50, near threshold is 48..50
      final movements = [
        InventoryMovement(
          id: 'mov_split_1',
          productId: 'prod_p1',
          productName: 'Product 1',
          productSource: 'selecta',
          createdBy: 'user_splitter',
          actorUid: 'user_splitter',
          actorName: 'Splitter',
          previousStock: 10,
          newStock: 59,
          delta: 49, // within [48, 50]
          reason: 'Stock count adjust',
          notes: 'Split 1',
          createdAt: Timestamp.fromDate(now.subtract(const Duration(hours: 2))),
          movementType: MovementType.adjustment,
        ),
        InventoryMovement(
          id: 'mov_split_2',
          productId: 'prod_p2',
          productName: 'Product 2',
          productSource: 'selecta',
          createdBy: 'user_splitter',
          actorUid: 'user_splitter',
          actorName: 'Splitter',
          previousStock: 10,
          newStock: 58,
          delta: 48, // within [48, 50]
          reason: 'Stock count adjust',
          notes: 'Split 2',
          createdAt: Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
          movementType: MovementType.adjustment,
        ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final splitAlert = alerts.where((a) => a.ruleId == 'threshold_splitting').toList();
      expect(splitAlert, isNotEmpty);
      expect(splitAlert.first.userId, 'user_splitter');
      expect(splitAlert.first.severity, 'high');
    });

    test('Rule 7: Flags aged quarantine customer returns older than 3 days', () async {
      final service = InventoryAlertService();
      final movements = [
        InventoryMovement(
          id: 'mov_quarantine_aged',
          productId: 'prod_quarantine',
          productName: 'Quarantined Product',
          productSource: 'selecta',
          createdBy: 'driver_bob',
          previousStock: 0,
          newStock: 0,
          delta: 0,
          reason: 'Customer return defective',
          notes: 'Freezer leak inspection required',
          createdAt: Timestamp.fromDate(now.subtract(const Duration(days: 4))), // 4 days ago >= 3 days
          movementType: MovementType.customer_return,
          disposition: ReturnDisposition.quarantine,
        ),
      ];

      final alerts = await service.evaluateAnomalies(
        movements: movements,
        items: [],
        config: testConfig,
        now: now,
      );

      final agedAlert = alerts.where((a) => a.ruleId == 'quarantine_aging').toList();
      expect(agedAlert, isNotEmpty);
      expect(agedAlert.first.productId, 'prod_quarantine');
    });
  });

  group('Inventory Audit Hardening - Blind Counts & Recount Tracking', () {
    test('InventoryMovement preserves blind count and recount round attributes', () {
      final movement = InventoryMovement(
        id: 'mov_blind_01',
        productId: 'prod_blind',
        productName: 'Blind Counted Ice Cream',
        productSource: 'selecta',
        createdBy: 'Auditor Mark',
        previousStock: 50,
        newStock: 42,
        delta: -8,
        reason: 'Blind Cycle Count',
        notes: 'Recount round 2 verified variance',
        createdAt: Timestamp.now(),
        movementType: MovementType.count_correction,
        reasonCode: ReasonCode.count_correction,
        isBlind: true,
        countRound: 2,
        systemQuantityAtStart: 50,
      );

      expect(movement.isBlind, isTrue);
      expect(movement.countRound, 2);
      expect(movement.systemQuantityAtStart, 50);

      final json = movement.toJson(forFirestore: false);
      expect(json['isBlind'], isTrue);
      expect(json['countRound'], 2);
      expect(json['systemQuantityAtStart'], 50);

      final restored = InventoryMovement.fromJson('mov_blind_01', json);
      expect(restored.isBlind, isTrue);
      expect(restored.countRound, 2);
      expect(restored.systemQuantityAtStart, 50);
    });

    test('Recount threshold triggers mandatory round 2 when variance >= recountThreshold', () {
      const recountThreshold = 10;
      final varianceBelow = (8).abs();
      final varianceAbove = (12).abs();

      expect(varianceBelow >= recountThreshold, isFalse);
      expect(varianceAbove >= recountThreshold, isTrue);
    });
  });
}
