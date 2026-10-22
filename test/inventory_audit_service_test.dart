import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/inventory_service.dart';

void main() {
  group('Inventory Audit & Discrepancy Models', () {
    test('StockDiscrepancy serializes to JSON correctly', () {
      final now = DateTime(2026, 10, 22, 10, 30);
      final discrepancy = StockDiscrepancy(
        productId: 'prod_123',
        productName: 'Cornetto Chocolate',
        productSource: 'selecta',
        discrepancyType: 'reserved_mismatch',
        expectedValue: 15,
        actualValue: 20,
        message: 'Reserved count does not match picklist total',
        detectedAt: now,
      );

      final json = discrepancy.toJson();
      expect(json['productId'], 'prod_123');
      expect(json['productName'], 'Cornetto Chocolate');
      expect(json['productSource'], 'selecta');
      expect(json['discrepancyType'], 'reserved_mismatch');
      expect(json['expectedValue'], 15);
      expect(json['actualValue'], 20);
      expect(json['status'], 'open');
    });

    test('StockAuditReport computes correct summary statistics', () {
      final now = DateTime(2026, 10, 22, 11, 0);
      final findings = [
        StockDiscrepancy(
          productId: 'p1',
          productName: 'Magnum Classic',
          productSource: 'selecta',
          discrepancyType: 'ledger_mismatch',
          expectedValue: 50,
          actualValue: 48,
          message: 'Direct product edit detected',
          detectedAt: now,
        ),
      ];

      final report = StockAuditReport(
        auditedAt: now,
        totalProductsAudited: 120,
        discrepanciesFound: 1,
        discrepancies: findings,
      );

      expect(report.totalProductsAudited, 120);
      expect(report.discrepanciesFound, 1);
      expect(report.discrepancies.first.productName, 'Magnum Classic');
    });

    test('CSV export generator generates valid CSV headers and records', () {
      final now = DateTime(2026, 10, 22, 12, 0);

      final movement = InventoryMovement(
        id: 'mov_999',
        productId: 'prod_selecta_01',
        productName: 'Selecta Super Thick Vanilla 1.3L',
        productSource: 'selecta',
        createdBy: 'Dealer Juan',
        previousStock: 25,
        newStock: 30,
        delta: 5,
        reason: 'Physical Audit',
        notes: 'Freezer #1 shelf recount, verified',
        createdAt: Timestamp.fromDate(now),
        movementType: MovementType.count_correction,
        reasonCode: ReasonCode.count_correction,
        referenceType: ReferenceType.manual,
        referenceId: 'audit_ref_01',
        referenceLabel: 'Cycle Count Shelf A',
        actorName: 'Dealer Juan',
        actorRole: 'dealer',
        actorUid: 'usr_dealer_1',
        appVersion: '1.0.0+51',
        deviceId: 'pixel_9_pro',
      );

      final csv = InventoryService.exportMovementsToCsv([movement]);
      expect(csv.contains('Movement ID,Date Time,Product ID,Product Name'), isTrue);
      expect(csv.contains('mov_999'), isTrue);
      expect(csv.contains('Selecta Super Thick Vanilla 1.3L'), isTrue);
      expect(csv.contains('Count Correction'), isTrue);
      expect(csv.contains('Dealer Juan'), isTrue);
    });

    test('updateStock rejects negative target quantities with ArgumentError', () async {
      final service = InventoryService();
      final item = InventoryItem(
        id: 'p_test',
        productName: 'Test Item',
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: 15,
        isActive: true,
        stockQuantity: 5,
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
      );

      expect(
        () => service.updateStock(
          item: item,
          newStockQuantity: -1,
          reason: 'Invalid Deduction',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Phase 8: InventoryMovement serialization preserves cross-cutting and audit fields', () {
      final now = DateTime(2026, 10, 22, 14, 30);
      final movement = InventoryMovement(
        id: 'mov_p8_01',
        productId: 'prod_selecta_cornetto',
        productName: 'Selecta Cornetto Disc Chocolate',
        productSource: 'selecta',
        previousStock: 40,
        newStock: 35,
        delta: -5,
        reason: 'Picklist Short-Pick (Out of Stock)',
        notes: 'Store: Aling Nena Tindahan (Picked: 15, Short: 5)',
        createdBy: 'Picker Alex',
        createdAt: Timestamp.fromDate(now),
        movementType: MovementType.pick,
        referenceType: ReferenceType.picklist,
        referenceId: 'del_1001',
        referenceLabel: 'Aling Nena Tindahan',
        previousReserved: 20,
        newReserved: 0,
        correlationId: 'picklist_del_1001',
        idempotencyKey: 'picklist_del_1001_prod_selecta_cornetto',
        sourceLocation: 'warehouse',
        targetLocation: 'van',
        isOverride: true,
        overrideReason: 'Scanner battery died, manual override',
        costPrice: 22.50,
        sellingPrice: 30.00,
        shortPickReason: ShortPickReason.out_of_stock,
        actorUid: 'usr_picker_2',
        actorRole: 'picker',
        actorName: 'Alex Cruz',
      );

      final json = movement.toJson();
      expect(json['correlationId'], 'picklist_del_1001');
      expect(json['idempotencyKey'], 'picklist_del_1001_prod_selecta_cornetto');
      expect(json['sourceLocation'], 'warehouse');
      expect(json['targetLocation'], 'van');
      expect(json['isOverride'], isTrue);
      expect(json['overrideReason'], 'Scanner battery died, manual override');
      expect(json['costPrice'], 22.50);
      expect(json['sellingPrice'], 30.00);
      expect(json['shortPickReason'], 'out_of_stock');

      final deserialized = InventoryMovement.fromJson('mov_p8_01', json);
      expect(deserialized.correlationId, 'picklist_del_1001');
      expect(deserialized.idempotencyKey, 'picklist_del_1001_prod_selecta_cornetto');
      expect(deserialized.sourceLocation, 'warehouse');
      expect(deserialized.targetLocation, 'van');
      expect(deserialized.isOverride, isTrue);
      expect(deserialized.overrideReason, 'Scanner battery died, manual override');
      expect(deserialized.costPrice, 22.50);
      expect(deserialized.sellingPrice, 30.00);
      expect(deserialized.shortPickReason, ShortPickReason.out_of_stock);
    });

    test('Phase 8: ReturnDisposition and quarantine/write-off movements serialize correctly', () {
      final now = DateTime(2026, 10, 22, 15, 0);
      final movement = InventoryMovement(
        id: 'mov_ret_01',
        productId: 'prod_other_cone',
        productName: 'Waffle Cones Box of 24',
        productSource: 'other',
        previousStock: 10,
        newStock: 10, // Stock did not increase because item was quarantined
        delta: 0,
        reason: 'Return Quarantined for Inspection',
        notes: 'Store: Bakery Mart (Quarantined for inspection: 3 units)',
        createdBy: 'Dealer Juan',
        createdAt: Timestamp.fromDate(now),
        movementType: MovementType.customer_return,
        referenceType: ReferenceType.return_doc,
        referenceId: 'del_ret_404',
        correlationId: 'return_approve_del_ret_404',
        sourceLocation: 'incoming',
        targetLocation: 'quarantine',
        disposition: ReturnDisposition.quarantine,
        reasonCode: ReasonCode.damaged,
      );

      final json = movement.toJson();
      expect(json['disposition'], 'quarantine');
      expect(json['targetLocation'], 'quarantine');
      expect(json['delta'], 0);

      final deserialized = InventoryMovement.fromJson('mov_ret_01', json);
      expect(deserialized.disposition, ReturnDisposition.quarantine);
      expect(deserialized.targetLocation, 'quarantine');

      final csv = InventoryService.exportMovementsToCsv([deserialized]);
      expect(csv.contains('Quarantine for Inspection'), isTrue);
      expect(csv.contains('return_approve_del_ret_404'), isTrue);
    });
  });
}
