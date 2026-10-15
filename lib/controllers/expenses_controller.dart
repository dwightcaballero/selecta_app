import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/expenses_services.dart';

/// Aggregation and filtering result for operating expenses.
/// Aggregation and filtering result for operating expenses.
class ExpenseFilterResult {
  final List<QueryDocumentSnapshot> filteredDocs;
  final double periodTotalAmount;
  final double periodCashAmount;
  final double periodOnlineAmount;
  final int todayCount;
  final int thisWeekCount;
  final int thisMonthCount;
  final int allCount;
  final int salesmanCount;
  final int dealerCount;

  const ExpenseFilterResult({
    required this.filteredDocs,
    required this.periodTotalAmount,
    this.periodCashAmount = 0.0,
    this.periodOnlineAmount = 0.0,
    this.todayCount = 0,
    this.thisWeekCount = 0,
    required this.thisMonthCount,
    required this.allCount,
    this.salesmanCount = 0,
    this.dealerCount = 0,
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

  /// Filters and aggregates expense documents according to selected tab type, period, and search query.
  ExpenseFilterResult filterExpenses({
    required List<QueryDocumentSnapshot> docs,
    required String selectedExpenseType, // ExpenseType.salesman or ExpenseType.dealer
    required String selectedPeriod,
    required String searchQuery,
    required DateTime now,
  }) {
    int todayCount = 0;
    int thisWeekCount = 0;
    int thisMonthCount = 0;
    int allTabCount = 0;
    int salesmanTotalCount = 0;
    int dealerTotalCount = 0;
    double periodTotalAmount = 0;
    double periodCashAmount = 0;
    double periodOnlineAmount = 0;
    final List<QueryDocumentSnapshot> filteredDocs = [];
    final cleanQuery = searchQuery.trim().toLowerCase();

    final startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // Week starts on Monday (Dart weekday: Monday=1, Sunday=7)
    final startOfWeek = DateTime(now.year, now.month, now.day, 0, 0, 0).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + 6, 23, 59, 59, 999);

    for (final doc in docs) {
      final expense = doc.data() as Expenses;
      final date = expense.expenseDate.toDate();

      if (expense.isSalesmanExpense) {
        salesmanTotalCount++;
      } else {
        dealerTotalCount++;
      }

      final matchesType = (selectedExpenseType == ExpenseType.salesman)
          ? expense.isSalesmanExpense
          : expense.isDealerExpense;

      if (!matchesType) continue;

      allTabCount++;

      final isToday = !date.isBefore(startOfToday) && !date.isAfter(endOfToday);
      final isThisWeek = !date.isBefore(startOfWeek) && !date.isAfter(endOfWeek);
      final isThisMonth = date.year == now.year && date.month == now.month;

      if (isToday) todayCount++;
      if (isThisWeek) thisWeekCount++;
      if (isThisMonth) thisMonthCount++;

      final bool matchesPeriod;
      switch (selectedPeriod) {
        case 'Today':
          matchesPeriod = isToday;
          break;
        case 'This Week':
          matchesPeriod = isThisWeek;
          break;
        case 'This Month':
          matchesPeriod = isThisMonth;
          break;
        case 'All':
        default:
          matchesPeriod = true;
          break;
      }

      final matchesSearch = cleanQuery.isEmpty || expense.description.toLowerCase().contains(cleanQuery);

      if (matchesPeriod) {
        periodTotalAmount += expense.expenseAmount;
        if (expense.isOnline) {
          periodOnlineAmount += expense.expenseAmount;
        } else {
          periodCashAmount += expense.expenseAmount;
        }
      }

      if (matchesPeriod && matchesSearch) {
        filteredDocs.add(doc);
      }
    }

    return ExpenseFilterResult(
      filteredDocs: filteredDocs,
      periodTotalAmount: periodTotalAmount,
      periodCashAmount: periodCashAmount,
      periodOnlineAmount: periodOnlineAmount,
      todayCount: todayCount,
      thisWeekCount: thisWeekCount,
      thisMonthCount: thisMonthCount,
      allCount: allTabCount,
      salesmanCount: salesmanTotalCount,
      dealerCount: dealerTotalCount,
    );
  }

  /// Creates a new expense record and logs the transaction.
  Future<void> createExpense({
    required String description,
    required double amount,
    required DateTime selectedDate,
    required String expenseType,
    required String paymentMethod,
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
      expenseType: expenseType,
      paymentMethod: paymentMethod,
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
    required String expenseType,
    required String paymentMethod,
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
      expenseType: expenseType,
      paymentMethod: paymentMethod,
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
