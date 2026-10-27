import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/endofday_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/dto/endofday_dto.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/return_proof.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/endofday_services.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/return_proof_service.dart';

class FakeEndOfDayServices extends Fake implements EndofdayServices {}
class FakeBreakdownService extends Fake implements BreakdownService {}
class FakeInventoryService extends Fake implements InventoryService {}

void main() {
  group('ReturnProof & ReturnProofItem Model Tests', () {
    test('ReturnProofItem serializes and deserializes correctly', () {
      const item = ReturnProofItem(
        deliveryId: 'del_1',
        productId: 'prod_1',
        productName: 'Cornetto Chocolate',
        returnedQuantity: 10,
        receivedQuantity: 8,
      );

      expect(item.variance, -2);
      expect(item.hasVariance, isTrue);

      final json = item.toJson();
      expect(json['deliveryId'], 'del_1');
      expect(json['productId'], 'prod_1');
      expect(json['productName'], 'Cornetto Chocolate');
      expect(json['returnedQuantity'], 10);
      expect(json['receivedQuantity'], 8);

      final reconstructed = ReturnProofItem.fromJson(json);
      expect(reconstructed.deliveryId, 'del_1');
      expect(reconstructed.productId, 'prod_1');
      expect(reconstructed.productName, 'Cornetto Chocolate');
      expect(reconstructed.returnedQuantity, 10);
      expect(reconstructed.receivedQuantity, 8);
      expect(reconstructed.variance, -2);
      expect(reconstructed.hasVariance, isTrue);
    });

    test('ReturnProofItem without variance returns variance 0 and hasVariance false', () {
      const item = ReturnProofItem(
        deliveryId: 'del_2',
        productId: 'prod_2',
        productName: 'Magnum Classic',
        returnedQuantity: 5,
        receivedQuantity: 5,
      );

      expect(item.variance, 0);
      expect(item.hasVariance, isFalse);
    });

    test('ReturnProof serializes to JSON and deserializes correctly', () {
      final now = Timestamp.now();
      final proof = ReturnProof(
        id: 'proof_100',
        storeName: 'Alpha Supermarket',
        proofDate: now,
        dayKey: '2026-10-26',
        deliveryIds: ['del_1', 'del_2'],
        imageUrl: 'https://storage.googleapis.com/proofs/proof_100.jpg',
        notes: 'Driver brought back 10 Cornettos',
        status: ReturnProofStatus.submitted,
        submittedBy: 'Juan Dela Cruz',
        submittedDate: now,
        items: const [
          ReturnProofItem(
            deliveryId: 'del_1',
            productId: 'prod_1',
            productName: 'Cornetto',
            returnedQuantity: 10,
            receivedQuantity: 10,
          ),
        ],
        history: [
          ReturnProofHistory(
            imageUrl: 'https://storage.googleapis.com/proofs/proof_100.jpg',
            status: ReturnProofStatus.submitted,
            actionBy: 'Juan Dela Cruz',
            actionDate: now,
            notes: 'Initial submission',
          ),
        ],
      );

      final json = proof.toJson();
      expect(json['id'], 'proof_100');
      expect(json['storeName'], 'Alpha Supermarket');
      expect(json['status'], ReturnProofStatus.submitted);
      expect((json['items'] as List).length, 1);
      expect((json['history'] as List).length, 1);

      final reconstructed = ReturnProof.fromJson(json, id: 'proof_100');
      expect(reconstructed.id, 'proof_100');
      expect(reconstructed.storeName, 'Alpha Supermarket');
      expect(reconstructed.status, ReturnProofStatus.submitted);
      expect(reconstructed.items.length, 1);
      expect(reconstructed.items.first.productName, 'Cornetto');
      expect(reconstructed.history.length, 1);
      expect(reconstructed.history.first.status, ReturnProofStatus.submitted);
      expect(reconstructed.history.first.actionBy, 'Juan Dela Cruz');
    });

    test('ReturnProof.empty provides safe default fallbacks', () {
      final empty = ReturnProof.empty();
      expect(empty.id, '');
      expect(empty.storeName, '');
      expect(empty.imageUrl, '');
      expect(empty.status, ReturnProofStatus.none);
      expect(empty.deliveryIds, isEmpty);
      expect(empty.items, isEmpty);
      expect(empty.history, isEmpty);
    });

    test('ReturnProof.copyWith correctly copies fields', () {
      final proof = ReturnProof(
        id: 'proof_1',
        storeName: 'Store 1',
        proofDate: Timestamp.now(),
        dayKey: '2026-10-26',
        deliveryIds: ['d1'],
        imageUrl: 'url1',
        status: ReturnProofStatus.submitted,
        submittedBy: 'Salesman',
      );

      final updated = proof.copyWith(
        status: ReturnProofStatus.confirmed,
        confirmedBy: 'Warehouse Manager',
      );

      expect(updated.id, 'proof_1');
      expect(updated.status, ReturnProofStatus.confirmed);
      expect(updated.confirmedBy, 'Warehouse Manager');
      expect(updated.submittedBy, 'Salesman');
    });
  });

  group('Delivery Model Return Proof Fields Tests', () {
    test('Delivery serializes and deserializes return proof fields', () {
      final now = Timestamp.now();
      final delivery = Delivery.empty().copyWith(
        storeName: 'Test Store',
        deliveryDate: now,
        createdDate: now,
        returnProofStatus: ReturnProofStatus.confirmed,
        returnProofId: 'proof_999',
        returnProofUrl: 'https://example.com/photo.jpg',
        returnProofNotes: 'Received in good condition',
        returnProofSubmittedBy: 'Salesman 1',
        returnProofSubmittedDate: now,
        returnProofConfirmedBy: 'Dealer 1',
        returnProofConfirmedDate: now,
        returnProofRejectReason: '',
        returnProofRequired: true,
      );

      final json = delivery.toJson();
      expect(json['returnProofStatus'], ReturnProofStatus.confirmed);
      expect(json['returnProofId'], 'proof_999');
      expect(json['returnProofUrl'], 'https://example.com/photo.jpg');
      expect(json['returnProofNotes'], 'Received in good condition');
      expect(json['returnProofSubmittedBy'], 'Salesman 1');
      expect(json['returnProofConfirmedBy'], 'Dealer 1');
      expect(json['returnProofRequired'], isTrue);

      final reconstructed = Delivery.fromJson(json);
      expect(reconstructed.returnProofStatus, ReturnProofStatus.confirmed);
      expect(reconstructed.returnProofId, 'proof_999');
      expect(reconstructed.returnProofUrl, 'https://example.com/photo.jpg');
      expect(reconstructed.returnProofNotes, 'Received in good condition');
      expect(reconstructed.returnProofSubmittedBy, 'Salesman 1');
      expect(reconstructed.returnProofConfirmedBy, 'Dealer 1');
      expect(reconstructed.returnProofRequired, isTrue);
    });

    test('Delivery defaults return proof fields if omitted from JSON', () {
      final json = {
        'storeName': 'Legacy Store',
        'deliveryDate': Timestamp.now(),
        'createdDate': Timestamp.now(),
      };

      final delivery = Delivery.fromJson(json);
      expect(delivery.returnProofStatus, ReturnProofStatus.none);
      expect(delivery.returnProofId, '');
      expect(delivery.returnProofUrl, '');
      expect(delivery.returnProofNotes, '');
      expect(delivery.returnProofSubmittedBy, '');
      expect(delivery.returnProofConfirmedBy, '');
      expect(delivery.returnProofRejectReason, '');
      expect(delivery.returnProofRequired, isFalse);
    });
  });

  group('ReturnProofService Gate Helpers Tests', () {
    test('deliveryHasReturns returns true when transactionStatus is Returned', () {
      final delivery = Delivery.empty().copyWith(
        storeName: 'Store 1',
        deliveryDate: Timestamp.now(),
        createdDate: Timestamp.now(),
        transactionStatus: DeliveryStatus.returned,
      );

      expect(ReturnProofService.deliveryHasReturns(delivery), isTrue);
    });

    test('deliveryHasReturns returns true when Delivered with returned quantity', () {
      final delivery = Delivery.empty().copyWith(
        storeName: 'Store 2',
        deliveryDate: Timestamp.now(),
        createdDate: Timestamp.now(),
        transactionStatus: DeliveryStatus.delivered,
        items: [
          const OrderItem(
            productId: 'p1',
            productName: 'Ice Cream',
            sellingPrice: 50.0,
            orderedQuantity: 10,
            pickedQuantity: 10,
            returnedQuantity: 2,
          ),
        ],
      );

      expect(ReturnProofService.deliveryHasReturns(delivery), isTrue);
    });

    test('deliveryHasReturns returns false when Delivered with 0 returned quantity', () {
      final delivery = Delivery.empty().copyWith(
        storeName: 'Store 3',
        deliveryDate: Timestamp.now(),
        createdDate: Timestamp.now(),
        transactionStatus: DeliveryStatus.delivered,
        items: [
          const OrderItem(
            productId: 'p1',
            productName: 'Ice Cream',
            sellingPrice: 50.0,
            orderedQuantity: 10,
            pickedQuantity: 10,
            returnedQuantity: 0,
          ),
        ],
      );

      expect(ReturnProofService.deliveryHasReturns(delivery), isFalse);
    });

    test('deliveryHasReturns returns false when Rescheduled even if quantities are set', () {
      final delivery = Delivery.empty().copyWith(
        storeName: 'Store 4',
        deliveryDate: Timestamp.now(),
        createdDate: Timestamp.now(),
        transactionStatus: DeliveryStatus.delivered,
        isRescheduled: true,
        items: [
          const OrderItem(
            productId: 'p1',
            productName: 'Ice Cream',
            sellingPrice: 50.0,
            orderedQuantity: 10,
            pickedQuantity: 10,
            returnedQuantity: 5,
          ),
        ],
      );

      expect(ReturnProofService.deliveryHasReturns(delivery), isFalse);
    });

    test('isDeliverySubjectToGate respects grandfathering cutoff date', () {
      final cutoff = Timestamp.fromDate(DateTime(2026, 11, 1));
      final preCutoff = Delivery.empty().copyWith(
        storeName: 'Pre',
        deliveryDate: Timestamp.fromDate(DateTime(2026, 10, 31)),
        createdDate: Timestamp.fromDate(DateTime(2026, 10, 31)),
      );
      final onCutoff = Delivery.empty().copyWith(
        storeName: 'On',
        deliveryDate: Timestamp.fromDate(DateTime(2026, 11, 1)),
        createdDate: Timestamp.fromDate(DateTime(2026, 11, 1)),
      );
      final postCutoff = Delivery.empty().copyWith(
        storeName: 'Post',
        deliveryDate: Timestamp.fromDate(DateTime(2026, 11, 2)),
        createdDate: Timestamp.fromDate(DateTime(2026, 11, 2)),
      );

      // Null cutoff -> inactive
      expect(ReturnProofService.isDeliverySubjectToGate(postCutoff, null), isFalse);

      // Pre-cutoff -> grandfathered (false)
      expect(ReturnProofService.isDeliverySubjectToGate(preCutoff, cutoff), isFalse);

      // On cutoff date -> active (true)
      expect(ReturnProofService.isDeliverySubjectToGate(onCutoff, cutoff), isTrue);

      // Post-cutoff -> active (true)
      expect(ReturnProofService.isDeliverySubjectToGate(postCutoff, cutoff), isTrue);
    });
  });

  group('EndOfDayDTO StoreReturnProofSummary Tests', () {
    test('hasUnconfirmedReturnProof is true if any return store is unconfirmed', () {
      const summaryUnconfirmed = StoreReturnProofSummary(
        storeName: 'Store 1',
        status: ReturnProofStatus.submitted,
        deliveriesWithIds: [],
        totalReturnedQty: 5,
        totalReturnedAmount: 250,
      );

      const summaryConfirmed = StoreReturnProofSummary(
        storeName: 'Store 2',
        status: ReturnProofStatus.confirmed,
        deliveriesWithIds: [],
        totalReturnedQty: 2,
        totalReturnedAmount: 100,
      );

      final dto = EndOfDayDTO.empty();
      dto.returnStores = [summaryUnconfirmed, summaryConfirmed];
      dto.hasUnconfirmedReturnProof = true;

      expect(dto.hasUnconfirmedReturnProof, isTrue);
      expect(dto.returnStores.length, 2);
    });

    test('hasUnconfirmedReturnProof is false when all return stores are confirmed or overridden', () {
      const summaryConfirmed = StoreReturnProofSummary(
        storeName: 'Store 1',
        status: ReturnProofStatus.confirmed,
        deliveriesWithIds: [],
        totalReturnedQty: 5,
        totalReturnedAmount: 250,
      );

      const summaryOverridden = StoreReturnProofSummary(
        storeName: 'Store 2',
        status: ReturnProofStatus.overridden,
        deliveriesWithIds: [],
        totalReturnedQty: 2,
        totalReturnedAmount: 100,
      );

      final dto = EndOfDayDTO.empty();
      dto.returnStores = [summaryConfirmed, summaryOverridden];
      dto.hasUnconfirmedReturnProof = false;

      expect(dto.hasUnconfirmedReturnProof, isFalse);
    });
  });

  group('EndOfDayController.validateBeforeBreakdown Gate Tests', () {
    final controller = EndOfDayController(
      endOfDayService: FakeEndOfDayServices(),
      breakdownService: FakeBreakdownService(),
      inventoryService: FakeInventoryService(),
    );

    test('Throws exception for salesman when hasUnconfirmedReturnProof is true', () {
      final dto = EndOfDayDTO.empty();
      dto.returnStores = [
        const StoreReturnProofSummary(
          storeName: 'Aling Nena Store',
          status: ReturnProofStatus.submitted,
          deliveriesWithIds: [],
          totalReturnedQty: 5,
          totalReturnedAmount: 250,
        ),
      ];
      dto.hasUnconfirmedReturnProof = true;

      expect(
        () => controller.validateBeforeBreakdown(
          endOfDayData: dto,
          breakdownId: 'b1',
          isDealer: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Aling Nena Store'),
          ),
        ),
      );
    });

    test('Does NOT throw for dealer even when hasUnconfirmedReturnProof is true', () {
      final dto = EndOfDayDTO.empty();
      dto.returnStores = [
        const StoreReturnProofSummary(
          storeName: 'Aling Nena Store',
          status: ReturnProofStatus.submitted,
          deliveriesWithIds: [],
          totalReturnedQty: 5,
          totalReturnedAmount: 250,
        ),
      ];
      dto.hasUnconfirmedReturnProof = true;

      // Should not throw because isDealer is true
      expect(
        () => controller.validateBeforeBreakdown(
          endOfDayData: dto,
          breakdownId: 'b1',
          isDealer: true,
        ),
        returnsNormally,
      );
    });

    test('Does NOT throw for salesman when all return proofs are confirmed', () {
      final dto = EndOfDayDTO.empty();
      dto.returnStores = [
        const StoreReturnProofSummary(
          storeName: 'Aling Nena Store',
          status: ReturnProofStatus.confirmed,
          deliveriesWithIds: [],
          totalReturnedQty: 5,
          totalReturnedAmount: 250,
        ),
      ];
      dto.hasUnconfirmedReturnProof = false;

      expect(
        () => controller.validateBeforeBreakdown(
          endOfDayData: dto,
          breakdownId: 'b1',
          isDealer: false,
        ),
        returnsNormally,
      );
    });
  });
}
