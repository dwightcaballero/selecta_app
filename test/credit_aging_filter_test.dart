import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/credit_controller.dart';
import 'package:selecta_ops/models/delivery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Credit Aging & Filter Tests', () {
    Delivery createMockDelivery({
      required String storeName,
      required double creditAmount,
      required DateTime deliveryDate,
    }) {
      return Delivery(
        storeName: storeName,
        remarks: '',
        transactionStatus: 'Delivered',
        imagePath: '',
        orderAmount: creditAmount,
        cashAmount: 0.0,
        onlineAmount: 0.0,
        creditAmount: creditAmount,
        returnAmount: 0.0,
        creditStatus: 'Unpaid',
        deliveryDate: Timestamp.fromDate(deliveryDate),
        items: const [],
        createdBy: 'Salesman',
        lastUpdatedBy: 'Salesman',
        createdDate: Timestamp.fromDate(deliveryDate),
        lastupdatedDate: Timestamp.fromDate(deliveryDate),
        createdPage: 'Delivery',
        lastUpdatedPage: 'Delivery',
        isInventoryReserved: true,
        isInventoryDeducted: true,
      );
    }

    test('CreditRecord calculates agingDays correctly and matches aging filters', () {
      final now = DateTime.now();

      // Current: 5 days old
      final recordCurrent = CreditRecord(
        id: 'doc_1',
        delivery: createMockDelivery(
          storeName: 'Store A',
          creditAmount: 500.0,
          deliveryDate: now.subtract(const Duration(days: 5)),
        ),
      );

      // Due Soon: 20 days old
      final recordDueSoon = CreditRecord(
        id: 'doc_2',
        delivery: createMockDelivery(
          storeName: 'Store B',
          creditAmount: 1200.0,
          deliveryDate: now.subtract(const Duration(days: 20)),
        ),
      );

      // Overdue: 45 days old
      final recordOverdue = CreditRecord(
        id: 'doc_3',
        delivery: createMockDelivery(
          storeName: 'Store C',
          creditAmount: 3000.0,
          deliveryDate: now.subtract(const Duration(days: 45)),
        ),
      );

      expect(recordCurrent.agingDays, inInclusiveRange(4, 6));
      expect(recordCurrent.matchesAgingFilter(CreditAgingFilter.all), isTrue);
      expect(recordCurrent.matchesAgingFilter(CreditAgingFilter.current), isTrue);
      expect(recordCurrent.matchesAgingFilter(CreditAgingFilter.dueSoon), isFalse);
      expect(recordCurrent.matchesAgingFilter(CreditAgingFilter.overdue), isFalse);

      expect(recordDueSoon.agingDays, inInclusiveRange(19, 21));
      expect(recordDueSoon.matchesAgingFilter(CreditAgingFilter.all), isTrue);
      expect(recordDueSoon.matchesAgingFilter(CreditAgingFilter.current), isFalse);
      expect(recordDueSoon.matchesAgingFilter(CreditAgingFilter.dueSoon), isTrue);
      expect(recordDueSoon.matchesAgingFilter(CreditAgingFilter.overdue), isFalse);

      expect(recordOverdue.agingDays, inInclusiveRange(44, 46));
      expect(recordOverdue.matchesAgingFilter(CreditAgingFilter.all), isTrue);
      expect(recordOverdue.matchesAgingFilter(CreditAgingFilter.current), isFalse);
      expect(recordOverdue.matchesAgingFilter(CreditAgingFilter.dueSoon), isFalse);
      expect(recordOverdue.matchesAgingFilter(CreditAgingFilter.overdue), isTrue);
    });

    test('CreditController sorting orders records correctly', () {
      final controller = CreditController();
      final now = DateTime.now();

      final record1 = CreditRecord(
        id: 'doc_1',
        delivery: createMockDelivery(
          storeName: 'Store 1',
          creditAmount: 500.0,
          deliveryDate: now.subtract(const Duration(days: 10)),
        ),
      );

      final record2 = CreditRecord(
        id: 'doc_2',
        delivery: createMockDelivery(
          storeName: 'Store 2',
          creditAmount: 2000.0,
          deliveryDate: now.subtract(const Duration(days: 40)),
        ),
      );

      // Highest credit amount first
      expect(controller.compareCreditRecords(record1, record2, CreditSort.highestAmount), greaterThan(0));
      expect(controller.compareCreditRecords(record2, record1, CreditSort.highestAmount), lessThan(0));

      // Oldest first
      expect(controller.compareCreditRecords(record1, record2, CreditSort.oldest), greaterThan(0));
      expect(controller.compareCreditRecords(record2, record1, CreditSort.oldest), lessThan(0));
    });
  });
}
