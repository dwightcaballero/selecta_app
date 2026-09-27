import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/expenses.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/expenses_services.dart';

/// Aggregation and filtering result for operating expenses.
class ExpenseFilterResult {
  final List<QueryDocumentSnapshot> filteredDocs;
  final double periodTotalAmount;
  final int thisMonthCount;
  final int allCount;

  const ExpenseFilterResult({
    required this.filteredDocs,
    required this.periodTotalAmount,
    required this.thisMonthCount,
    required this.allCount,
  });
}

/// Controller encapsulating business logic, Firestore CRUD operations,
/// audit logging, role verification, and period filtering for Operating Expenses.
class ExpensesController {
  final ExpensesService _expensesService = ExpensesService();

  /// Real-time stream of all expense documents.
  Stream<QuerySnapshot> getExpensesStream() => _expensesService.getListExpenses();

  /// Checks if the current user possesses the Dealer business role.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Returns the display name of the currently authenticated user.
  String getCurrentUserDisplayName() {
    return authService.value.currentUser?.displayName ?? 'Unknown';
  }

  /// Filters and aggregates expense documents according to selected period and search query.
  ExpenseFilterResult filterExpenses({
    required List<QueryDocumentSnapshot> docs,
    required String selectedPeriod,
    required String searchQuery,
    required DateTime now,
  }) {
    int thisMonthCount = 0;
    double periodTotalAmount = 0;
    final List<QueryDocumentSnapshot> filteredDocs = [];
    final cleanQuery = searchQuery.trim().toLowerCase();

    for (final doc in docs) {
      final expense = doc.data() as Expenses;
      final date = expense.expenseDate.toDate();
      final isThisMonth = date.year == now.year && date.month == now.month;

      if (isThisMonth) thisMonthCount++;

      final matchesPeriod = selectedPeriod == 'All' || isThisMonth;
      final matchesSearch = cleanQuery.isEmpty || expense.description.toLowerCase().contains(cleanQuery);

      if (matchesPeriod) {
        periodTotalAmount += expense.expenseAmount;
      }

      if (matchesPeriod && matchesSearch) {
        filteredDocs.add(doc);
      }
    }

    return ExpenseFilterResult(
      filteredDocs: filteredDocs,
      periodTotalAmount: periodTotalAmount,
      thisMonthCount: thisMonthCount,
      allCount: docs.length,
    );
  }

  /// Creates a new expense record and logs the transaction.
  Future<void> createExpense({
    required String description,
    required double amount,
    required DateTime selectedDate,
  }) async {
    final user = getCurrentUserDisplayName();
    final newRecord = Expenses(
      description: description,
      expenseAmount: amount,
      expenseDate: Timestamp.fromDate(selectedDate),
      createdBy: user,
      lastUpdatedBy: user,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.expenses,
      lastUpdatedPage: AppPages.expenses,
    );

    _expensesService.addExpenses(newRecord);
    await Helperfunctions.logCreate(description, newRecord.toJson(), page: AppPages.expenses);
  }

  /// Updates an existing expense record and logs the audit trail.
  Future<void> updateExpense({
    required String recID,
    required Expenses existingRecord,
    required String description,
    required double amount,
    required DateTime selectedDate,
  }) async {
    final user = getCurrentUserDisplayName();
    final updatedRecord = existingRecord.copyWith(
      description: description,
      expenseAmount: amount,
      expenseDate: Timestamp.fromDate(selectedDate),
      createdBy: existingRecord.createdBy,
      lastUpdatedBy: user,
      createdDate: existingRecord.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: existingRecord.createdPage,
      lastUpdatedPage: AppPages.expenses,
    );

    _expensesService.updateExpenses(recID, updatedRecord);
    await Helperfunctions.logUpdate(
      description,
      existingRecord.toJson(),
      updatedRecord.toJson(),
      page: AppPages.expenses,
    );
  }

  /// Deletes an expense record and logs the transaction.
  Future<void> deleteExpense({
    required String recID,
    required Expenses existingRecord,
  }) async {
    _expensesService.deleteExpenses(recID);
    await Helperfunctions.logDelete(
      existingRecord.description,
      existingRecord.toJson(),
      page: AppPages.expenses,
    );
  }
}
