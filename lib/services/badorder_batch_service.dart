import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/badorder_batch.dart';

// ignore: constant_identifier_names
const String BADORDER_BATCH_COLLECTION_REF = 'badorder_batch';

class BadOrderBatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final CollectionReference<BadOrderBatch> _batchRef;

  BadOrderBatchService() {
    _batchRef = _firestore
        .collection(BADORDER_BATCH_COLLECTION_REF)
        .withConverter<BadOrderBatch>(
          fromFirestore: (snapshots, _) =>
              BadOrderBatch.fromJson(snapshots.data()!, snapshots.id),
          toFirestore: (batch, _) => batch.toJson(),
        );
  }

  Stream<QuerySnapshot<BadOrderBatch>> getListBatches() {
    return _batchRef.orderBy('pulloutDate', descending: true).snapshots();
  }

  Future<DocumentSnapshot<BadOrderBatch>> getBatch(String batchId) {
    return _batchRef.doc(batchId).get();
  }

  /// Creates a new batch record and atomically updates all linked bad orders
  /// to 'Warehouse Pullout' status and attaches the batch ID & batch number.
  Future<String> createBatch(BadOrderBatch batch) async {
    final batchDocRef = _batchRef.doc();
    final batchId = batchDocRef.id;
    final toSave = batch.copyWith(id: batchId);

    final writeBatch = _firestore.batch();
    writeBatch.set(batchDocRef, toSave);

    final now = Timestamp.now();
    for (final badOrderId in batch.badOrderIds) {
      final boRef = _firestore.collection('badorder').doc(badOrderId);
      writeBatch.update(boRef, {
        'status': BadOrderStatus.warehousePullout,
        'batchId': batchId,
        'batchNumber': batch.batchNumber,
        'lastUpdatedBy': batch.createdBy,
        'lastupdatedDate': now,
        'lastUpdatedPage': AppPages.badOrder,
      });
    }

    await writeBatch.commit();
    return batchId;
  }

  /// Settles the batch with the supplier's credit memo / refund details
  /// and cascades 'Settled' status to all individual bad order records.
  Future<void> settleBatch({
    required String batchId,
    required BadOrderBatch existingBatch,
    required double supplierRefundAmount,
    required String supplierCreditMemoNo,
    required DateTime supplierRefundDate,
    String adjustmentReason = '',
    required String user,
  }) async {
    final now = Timestamp.now();
    final writeBatch = _firestore.batch();

    final batchDocRef = _batchRef.doc(batchId);
    writeBatch.update(batchDocRef, {
      'status': BadOrderStatus.settled,
      'isSupplierRefunded': true,
      'supplierRefundAmount': supplierRefundAmount,
      'supplierCreditMemoNo': supplierCreditMemoNo,
      'supplierRefundDate': Timestamp.fromDate(supplierRefundDate),
      'adjustmentReason': adjustmentReason,
      'supplierRefundBy': user,
      'lastUpdatedBy': user,
      'lastupdatedDate': now,
    });

    for (final badOrderId in existingBatch.badOrderIds) {
      final boRef = _firestore.collection('badorder').doc(badOrderId);
      writeBatch.update(boRef, {
        'status': BadOrderStatus.settled,
        'lastUpdatedBy': user,
        'lastupdatedDate': now,
        'lastUpdatedPage': AppPages.badOrder,
      });
    }

    await writeBatch.commit();
  }

  /// Cancels/deletes an unsettled batch and reverts its bad orders back to 'Store Pullout'.
  Future<void> deleteBatch({
    required String batchId,
    required BadOrderBatch existingBatch,
    required String user,
  }) async {
    final now = Timestamp.now();
    final writeBatch = _firestore.batch();

    final batchDocRef = _batchRef.doc(batchId);
    writeBatch.delete(batchDocRef);

    for (final badOrderId in existingBatch.badOrderIds) {
      final boRef = _firestore.collection('badorder').doc(badOrderId);
      writeBatch.update(boRef, {
        'status': BadOrderStatus.storePullout,
        'batchId': FieldValue.delete(),
        'batchNumber': FieldValue.delete(),
        'lastUpdatedBy': user,
        'lastupdatedDate': now,
        'lastUpdatedPage': AppPages.badOrder,
      });
    }

    await writeBatch.commit();
  }
}
