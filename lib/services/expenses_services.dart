import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/expenses.dart';

// ignore: constant_identifier_names
const String EXPENSES_COLLECTION_REF = 'expenses';

class ExpensesService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _expensesRef;

  ExpensesService() {
    _expensesRef = _firestore
        .collection(EXPENSES_COLLECTION_REF)
        .withConverter<Expenses>(
          fromFirestore: (snapshots, _) => Expenses.fromJson(snapshots.data()!),
          toFirestore: (expense, _) => expense.toJson(),
        );
  }

  Stream<QuerySnapshot> getListExpenses() {
    return _expensesRef.orderBy('expenseDate', descending: true).snapshots();
  }

  Future<double?> getTotalExpensesForEndOfDay(DateTime expenseDate) async {
    final startOfDay = DateTime(
      expenseDate.year,
      expenseDate.month,
      expenseDate.day,
      0,
      0,
      0,
    );

    final endOfDay = DateTime(
      expenseDate.year,
      expenseDate.month,
      expenseDate.day,
      23,
      59,
      59,
    );

    try {
      // 1. Build the filtered query
      Query query = FirebaseFirestore.instance
          .collection(EXPENSES_COLLECTION_REF)
          .where(
            'expenseDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'expenseDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          );

      // 2. Attach the sum aggregate function
      AggregateQuerySnapshot snapshot = await query
          .aggregate(sum('expenseAmount'))
          .get();

      // 3. Extract and return the calculation result
      return snapshot.getSum('expenseAmount');
    } catch (e) {
      return null;
    }
  }

  void addExpenses(Expenses expense) {
    _expensesRef.add(expense);
  }

  void updateExpenses(String expenseID, Expenses expense) {
    _expensesRef.doc(expenseID).update(expense.toJson());
  }

  void deleteExpenses(String expenseID) {
    _expensesRef.doc(expenseID).delete();
  }
}
