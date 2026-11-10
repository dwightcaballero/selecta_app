import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/return_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';

// ignore: subtype_of_sealed_class
class MockQueryDocumentSnapshot extends Fake implements QueryDocumentSnapshot<Delivery> {
  final Delivery _data;
  final String _id;

  MockQueryDocumentSnapshot(this._id, this._data);

  @override
  Delivery data() => _data;

  @override
  String get id => _id;
}

void main() {
  group('Return banner and active return lifecycle tests', () {
    final returnController = ReturnController();

    test('Return approved by dealer but not yet finalized or redelivered is counted as Active', () {
      final now = DateTime.now();

      // Return that has been approved by dealer, but not rescheduled and not finalized
      final approvedReturn = Delivery.empty().copyWith(
        storeName: 'Test Store 1',
        transactionStatus: DeliveryStatus.returned,
        isReturnApprovedByDealer: true,
        returnApprovedDate: Timestamp.fromDate(now),
        isReturnIncoming: false,
        isRescheduled: false,
        isReturnFinalized: false,
        lastupdatedDate: Timestamp.fromDate(now),
        returnAmount: 500,
        orderAmount: 500,
      );

      final doc = MockQueryDocumentSnapshot('del_1', approvedReturn);
      final activeList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Active',
      );

      expect(activeList.length, 1);
      final metrics = returnController.computeMetrics([doc]);
      expect(metrics.totalCount, 1);
      expect(metrics.totalAmount, 500.0);
    });

    test('Return that has been redelivered (rescheduled) is moved to Completed and excluded from Active', () {
      final now = DateTime.now();

      final rescheduledReturn = Delivery.empty().copyWith(
        storeName: 'Test Store 2',
        transactionStatus: DeliveryStatus.returned,
        isReturnApprovedByDealer: true,
        isRescheduled: true,
        rescheduledToDeliveryId: 'new_del_123',
        rescheduledDate: Timestamp.fromDate(now),
        isReturnFinalized: false,
        lastupdatedDate: Timestamp.fromDate(now),
        returnAmount: 300,
        orderAmount: 300,
      );

      final doc = MockQueryDocumentSnapshot('del_2', rescheduledReturn);
      final activeList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Active',
      );
      expect(activeList.length, 0);

      final completedList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Completed',
      );
      expect(completedList.length, 1);

      final metrics = returnController.computeMetrics([doc]);
      expect(metrics.totalCount, 0);
      expect(metrics.totalAmount, 0.0);
    });

    test('Return that has been finalized is moved to Completed and excluded from Active', () {
      final now = DateTime.now();

      final finalizedReturn = Delivery.empty().copyWith(
        storeName: 'Test Store 3',
        transactionStatus: DeliveryStatus.returned,
        isReturnApprovedByDealer: true,
        isRescheduled: false,
        isReturnFinalized: true,
        returnFinalizedDate: Timestamp.fromDate(now),
        lastupdatedDate: Timestamp.fromDate(now),
        returnAmount: 450,
        orderAmount: 450,
      );

      final doc = MockQueryDocumentSnapshot('del_3', finalizedReturn);
      final activeList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Active',
      );
      expect(activeList.length, 0);

      final completedList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Completed',
      );
      expect(completedList.length, 1);

      final metrics = returnController.computeMetrics([doc]);
      expect(metrics.totalCount, 0);
      expect(metrics.totalAmount, 0.0);
    });

    test('Partial return approved by dealer but not yet redelivered or finalized is counted as Active', () {
      final now = DateTime.now();

      final partialApprovedReturn = Delivery.empty().copyWith(
        storeName: 'Partial Store',
        transactionStatus: DeliveryStatus.delivered,
        isReturnApprovedByDealer: true,
        isReturnIncoming: false,
        isRescheduled: false,
        isReturnFinalized: false,
        returnAmount: 200,
        orderAmount: 1000,
        lastupdatedDate: Timestamp.fromDate(now),
      );

      final doc = MockQueryDocumentSnapshot('del_4', partialApprovedReturn);
      final activeList = returnController.filterReturns(
        docs: [doc],
        searchQuery: '',
        filterTab: 'Active',
      );
      expect(activeList.length, 1);

      final metrics = returnController.computeMetrics([doc]);
      expect(metrics.totalCount, 1);
      expect(metrics.totalAmount, 200.0);
    });
  });
}

