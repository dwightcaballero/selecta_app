import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/inventory_movement.dart';

void main() {
  group('InventoryMovement Model Tests', () {
    test('parses legacy movement json without new audit fields correctly', () {
      final now = Timestamp.now();
      final legacyJson = <String, Object?>{
        'productId': 'prod_123',
        'productName': 'Cornetto Chocolate',
        'productSource': 'selecta',
        'previousStock': 100,
        'newStock': 80,
        'delta': -20,
        'reason': 'Van Load (Delivery #DEL-001)',
        'notes': 'Loaded onto Van A',
        'createdBy': 'John Doe',
        'createdAt': now,
      };

      final movement = InventoryMovement.fromJson('doc_1', legacyJson);

      expect(movement.id, 'doc_1');
      expect(movement.productId, 'prod_123');
      expect(movement.productName, 'Cornetto Chocolate');
      expect(movement.previousStock, 100);
      expect(movement.newStock, 80);
      expect(movement.delta, -20);
      expect(movement.reason, 'Van Load (Delivery #DEL-001)');
      expect(movement.notes, 'Loaded onto Van A');
      expect(movement.createdBy, 'John Doe');
      expect(movement.displayActor, 'John Doe');

      // Mapped legacy fields:
      expect(movement.movementType, MovementType.van_load);
      expect(movement.reasonCode, isNull);
      expect(movement.referenceType, isNull);
      expect(movement.clamped, isFalse);
      expect(movement.source, 'app');
      expect(movement.hasPhysicalStockChange, isTrue);
      expect(movement.hasReservedStockChange, isFalse);
    });

    test('maps legacy reason keywords to appropriate MovementType', () {
      expect(MovementType.fromLegacyReason('PO Replenish #12'), MovementType.receipt);
      expect(MovementType.fromLegacyReason('Picklist #PL-9 fulfilled'), MovementType.pick);
      expect(MovementType.fromLegacyReason('Van Return from Driver'), MovementType.van_return);
      expect(MovementType.fromLegacyReason('PO placed (incoming)'), MovementType.incoming_added);
      expect(MovementType.fromLegacyReason('Cancelled order reversal'), MovementType.reversal);
      expect(MovementType.fromLegacyReason('Customer Return Restock'), MovementType.customer_return);
      expect(MovementType.fromLegacyReason('Settlement deduction'), MovementType.settlement);
      expect(MovementType.fromLegacyReason('Count Correction Audit'), MovementType.count_correction);
      expect(MovementType.fromLegacyReason('Expired stock disposal'), MovementType.damage_expiry);
      expect(MovementType.fromLegacyReason('Arbitrary reason'), MovementType.adjustment);
    });

    test('serializes and deserializes modern audit movement with round-trip fidelity', () {
      final now = Timestamp.now();
      final original = InventoryMovement(
        id: 'mov_99',
        productId: 'prod_selecta_55',
        productName: 'Magnum Almond',
        productSource: 'selecta',
        previousStock: 50,
        newStock: 0,
        delta: -50,
        reason: 'Daily Van Load',
        notes: 'Clamped due to insufficient physical stock on hand',
        createdBy: 'Alice Admin',
        createdAt: now,
        movementType: MovementType.van_load,
        reasonCode: ReasonCode.lost,
        referenceType: ReferenceType.van_load,
        referenceId: 'VL-888',
        referenceLabel: 'Route North Van 2',
        previousReserved: 20,
        newReserved: 10,
        previousIncoming: 100,
        newIncoming: 100,
        requestedQuantity: 60,
        clamped: true,
        actorUid: 'usr_alice_123',
        actorRole: 'dealer',
        actorName: 'Alice Admin',
        source: 'app',
        deviceId: 'device_tablet_xyz',
        appVersion: '1.0.0+51',
        batchId: 'batch_van_load_20261022',
      );

      final json = original.toJson();
      final parsed = InventoryMovement.fromJson(original.id, json);

      expect(parsed.id, original.id);
      expect(parsed.productId, original.productId);
      expect(parsed.movementType, MovementType.van_load);
      expect(parsed.reasonCode, ReasonCode.lost);
      expect(parsed.referenceType, ReferenceType.van_load);
      expect(parsed.referenceId, 'VL-888');
      expect(parsed.referenceLabel, 'Route North Van 2');
      expect(parsed.previousReserved, 20);
      expect(parsed.newReserved, 10);
      expect(parsed.reservedDelta, -10);
      expect(parsed.requestedQuantity, 60);
      expect(parsed.clamped, isTrue);
      expect(parsed.actorUid, 'usr_alice_123');
      expect(parsed.actorRole, 'dealer');
      expect(parsed.actorName, 'Alice Admin');
      expect(parsed.displayActor, 'Alice Admin');
      expect(parsed.source, 'app');
      expect(parsed.deviceId, 'device_tablet_xyz');
      expect(parsed.appVersion, '1.0.0+51');
      expect(parsed.batchId, 'batch_van_load_20261022');
      expect(parsed.hasPhysicalStockChange, isTrue);
      expect(parsed.hasReservedStockChange, isTrue);
      expect(parsed.hasIncomingStockChange, isFalse);
    });
  });
}
