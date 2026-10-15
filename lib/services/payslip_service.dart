import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/models/payslip.dart';
import 'package:selecta_ops/models/users.dart';

// ignore: constant_identifier_names
const String PAYSLIPS_COLLECTION_REF = 'payslips';

class PayslipService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _payslipsRef =>
      _firestore.collection(PAYSLIPS_COLLECTION_REF);

  /// Streams all payslips issued under a specific dealer
  Stream<List<Payslip>> getPayslipsForDealer(String dealerName) {
    return _payslipsRef
        .where('dealerName', isEqualTo: dealerName)
        .orderBy('createdDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payslip.fromSnapshot(doc))
            .toList());
  }

  /// Streams all payslips for a specific salesman
  Stream<List<Payslip>> getPayslipsForSalesman(String salesmanUsername) {
    return _payslipsRef
        .where('salesmanUsername', isEqualTo: salesmanUsername)
        .orderBy('createdDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payslip.fromSnapshot(doc))
            .where((p) => p.status != PayslipStatus.draft) // Salesmen only see issued/paid
            .toList());
  }

  /// Retrieves all salesmen belonging to a dealer
  Future<List<Users>> getSalesmenForDealer(String dealerName) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: BusinessRole.salesman)
          .where('dealerName', isEqualTo: dealerName)
          .get();

      return snapshot.docs.map((doc) => Users.fromSnapshot(doc)).toList();
    } catch (e) {
      debugPrint('Error getting salesmen for dealer: $e');
      return [];
    }
  }

  /// Updates or saves a salesman's persistent base daily rate in their user profile
  Future<void> updateSalesmanDailyRate(String salesmanUsername, double rate) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: salesmanUsername)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        await query.docs.first.reference.update({'dailyRate': rate});
      }
    } catch (e) {
      debugPrint('Error updating salesman daily rate: $e');
    }
  }

  /// Fetches salesman expenses within a given weekly date range.
  Future<List<Expenses>> getSalesmanExpensesForRange({
    required String salesmanUsername,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final startOfRange = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final endOfRange = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    try {
      final snapshot = await _firestore
          .collection('expenses')
          .where('expenseDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
          .where('expenseDate', isLessThanOrEqualTo: Timestamp.fromDate(endOfRange))
          .get();

      final list = snapshot.docs
          .map((doc) => Expenses.fromSnapshot(doc))
          .where((exp) {
            // Check if logged by this salesman or explicitly marked for them
            return exp.createdBy.toLowerCase() == salesmanUsername.toLowerCase() ||
                (exp.expenseType == ExpenseType.salesman &&
                    exp.createdBy.toLowerCase().contains(salesmanUsername.toLowerCase()));
          })
          .toList();

      return list;
    } catch (e) {
      debugPrint('Error getting salesman expenses: $e');
      return [];
    }
  }

  /// Creates a new payslip
  Future<String> createPayslip(Payslip payslip) async {
    final docRef = await _payslipsRef.add(payslip.toJson());
    return docRef.id;
  }

  /// Updates an existing payslip
  Future<void> updatePayslip(String id, Payslip payslip) async {
    await _payslipsRef.doc(id).update(payslip.toJson());
  }

  /// Deletes a payslip (draft or dealer action)
  Future<void> deletePayslip(String id) async {
    await _payslipsRef.doc(id).delete();
  }

  /// Updates the status of a payslip (e.g. Issued, Acknowledged, Paid)
  Future<void> updateStatus(String id, String status) async {
    final Map<String, dynamic> updateData = {
      'status': status,
      'lastUpdatedDate': Timestamp.now(),
    };

    if (status == PayslipStatus.issued) {
      updateData['issuedDate'] = Timestamp.now();
    } else if (status == PayslipStatus.acknowledged || status == PayslipStatus.paid) {
      updateData['acknowledgedDate'] = Timestamp.now();
    }

    await _payslipsRef.doc(id).update(updateData);
  }
}
