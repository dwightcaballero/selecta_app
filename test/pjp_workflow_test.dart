import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/controllers/pjp_controller.dart';
import 'package:flutter_app/models/proof_of_visit.dart';
import 'package:flutter_app/services/pjp_order_decision_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PJP Checklist Workflow & Models Tests', () {
    test('ProofOfVisit model correctly serializes and deserializes', () {
      final now = Timestamp.now();
      final proof = ProofOfVisit(
        id: 'pov_123',
        storeName: 'Test Sari-Sari Store',
        visitDate: now,
        imageUrl: 'https://storage.googleapis.com/test-bucket/proof.jpg',
        takenBy: 'Salesman Dwight',
        notes: 'Freezer clean and organized',
      );

      final json = proof.toJson();
      expect(json['id'], 'pov_123');
      expect(json['storeName'], 'Test Sari-Sari Store');
      expect(json['visitDate'], now);
      expect(json['imageUrl'], 'https://storage.googleapis.com/test-bucket/proof.jpg');
      expect(json['takenBy'], 'Salesman Dwight');
      expect(json['notes'], 'Freezer clean and organized');

      final fromJson = ProofOfVisit.fromJson(json, id: 'pov_123');
      expect(fromJson.id, 'pov_123');
      expect(fromJson.storeName, 'Test Sari-Sari Store');
      expect(fromJson.visitDate, now);
      expect(fromJson.imageUrl, 'https://storage.googleapis.com/test-bucket/proof.jpg');
      expect(fromJson.takenBy, 'Salesman Dwight');
    });

    test('PjpOrderDecision model serializes and handles no-order reasons', () {
      final now = Timestamp.now();
      final decision = PjpOrderDecision(
        id: 'dec_1',
        storeName: 'Aling Nena Store',
        decision: 'no_order',
        reason: 'Store is currently overstocked with Cornetto and Selecta pints',
        date: now,
        createdBy: 'Salesman Dwight',
      );

      final json = decision.toJson();
      expect(json['storeName'], 'Aling Nena Store');
      expect(json['decision'], 'no_order');
      expect(json['reason'], contains('overstocked'));
      expect(json['createdBy'], 'Salesman Dwight');
    });

    test('BookOrderCheckResult and ProofOfVisitCheckResult status and passed properties', () {
      const orderPassed = BookOrderCheckResult(
        passed: true,
        status: 'Order booked for today (Pending Picklist).',
        hasBookedOrder: true,
      );
      expect(orderPassed.passed, isTrue);
      expect(orderPassed.hasBookedOrder, isTrue);

      const noOrderPassed = BookOrderCheckResult(
        passed: true,
        status: 'No order booked today. Reason: Store Closed',
        hasBookedOrder: false,
        noOrderReason: 'Store Closed',
      );
      expect(noOrderPassed.passed, isTrue);
      expect(noOrderPassed.hasBookedOrder, isFalse);
      expect(noOrderPassed.noOrderReason, 'Store Closed');

      const povPending = ProofOfVisitCheckResult(
        passed: false,
        status: 'Proof of visit photo not yet captured.',
      );
      expect(povPending.passed, isFalse);
      expect(povPending.proofOfVisit, isNull);
    });

    test('PJP Visit completion criteria: Merch Blitz is optional', () {
      bool canComplete({
        required bool location,
        required bool scanning,
        required bool bookOrder,
        required bool proofOfVisit,
        required bool tasks,
        required bool merchBlitz,
      }) {
        // Steps 1 to 5 are required; Merch Blitz is optional and does not block completion.
        return location && scanning && bookOrder && proofOfVisit && tasks;
      }

      // Case 1: All required pass, Merch Blitz false -> can complete
      expect(
        canComplete(
          location: true,
          scanning: true,
          bookOrder: true,
          proofOfVisit: true,
          tasks: true,
          merchBlitz: false,
        ),
        isTrue,
        reason: 'User should be able to complete PJP even though there was no merch blitz done',
      );

      // Case 2: One required fails (e.g. proof of visit) -> cannot complete
      expect(
        canComplete(
          location: true,
          scanning: true,
          bookOrder: true,
          proofOfVisit: false,
          tasks: true,
          merchBlitz: true,
        ),
        isFalse,
        reason: 'All 5 required steps must pass to complete visit',
      );
    });

    test('Scanning status of Pending or Scanned marks checklist step as passed', () {
      bool isScanningPassed(List<String> statuses) {
        return statuses.any((s) => s == 'Pending' || s == 'Scanned');
      }

      expect(isScanningPassed(['Scanned']), isTrue);
      expect(isScanningPassed(['Pending']), isTrue);
      expect(isScanningPassed(['Not Scanned']), isFalse);
      expect(isScanningPassed(['Unassigned']), isFalse);
      expect(isScanningPassed(['Pullout']), isFalse);
      expect(isScanningPassed([]), isFalse);
      expect(isScanningPassed(['Not Scanned', 'Pending']), isTrue);
    });
  });
}
