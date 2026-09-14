import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/purchaseorder.dart';

void main() {
  test('purchase order stores and serializes invoice image path', () {
    final order = Purchaseorder(
      invoiceNumber: 'INV-1001',
      orderAmount: 250.0,
      orderDate: Timestamp.fromDate(DateTime(2026, 9, 14)),
      overpayment: 10.0,
      isSettled: false,
      createdBy: 'Alice',
      lastUpdatedBy: 'Alice',
      createdDate: Timestamp.fromDate(DateTime(2026, 9, 13)),
      lastupdatedDate: Timestamp.fromDate(DateTime(2026, 9, 14)),
      invoiceAmount: 260.0,
      imagePath: 'https://example.com/invoice.jpg',
      invoiceDate: Timestamp.fromDate(DateTime(2026, 9, 14)),
    );

    expect(order.imagePath, 'https://example.com/invoice.jpg');
    expect(order.toJson()['imagePath'], 'https://example.com/invoice.jpg');
    expect(Purchaseorder.empty().imagePath, isEmpty);
  });
}
