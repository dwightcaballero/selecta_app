import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/models/payslip.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/payslip_service.dart';

class PayslipGroupedResult {
  final Payslip? currentPayslip;
  final List<Payslip> previousPayslips;

  const PayslipGroupedResult({
    required this.currentPayslip,
    required this.previousPayslips,
  });
}

class PayslipController {
  final PayslipService _service = PayslipService();
  static final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  /// Streams payslips for dealer
  Stream<List<Payslip>> getDealerPayslipsStream(String dealerName) {
    return _service.getPayslipsForDealer(dealerName);
  }

  /// Streams payslips for salesman
  Stream<List<Payslip>> getSalesmanPayslipsStream(String salesmanUsername) {
    return _service.getPayslipsForSalesman(salesmanUsername);
  }

  /// Checks if active user is a dealer
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Gets current user profile
  Future<Users?> getCurrentUser() async {
    return await KVariables.getUser();
  }

  /// Gets all salesmen assigned to the dealer
  Future<List<Users>> getSalesmenForDealer(String dealerName) async {
    return await _service.getSalesmenForDealer(dealerName);
  }

  /// Updates a salesman's persistent base daily rate
  Future<void> updateSalesmanDailyRate(String salesmanUsername, double rate) async {
    await _service.updateSalesmanDailyRate(salesmanUsername, rate);
  }

  /// Fetches expenses logged by a salesman during a week range
  Future<List<Expenses>> getSalesmanExpensesForWeek({
    required String salesmanUsername,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return await _service.getSalesmanExpensesForRange(
      salesmanUsername: salesmanUsername,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Creates a payslip and logs audit record
  Future<String> createPayslip(Payslip payslip) async {
    final id = await _service.createPayslip(payslip);
    await Helperfunctions.logCreate(
      'Payslip ${payslip.payslipNumber} for ${payslip.salesmanUsername}',
      payslip.toJson(),
      page: AppPages.payslip,
    );
    return id;
  }

  /// Updates a payslip and logs audit record
  Future<void> updatePayslip(String id, Payslip oldRecord, Payslip newRecord) async {
    await _service.updatePayslip(id, newRecord);
    await Helperfunctions.logUpdate(
      'Payslip ${newRecord.payslipNumber}',
      oldRecord.toJson(),
      newRecord.toJson(),
      page: AppPages.payslip,
    );
  }

  /// Deletes a payslip
  Future<void> deletePayslip(String id, Payslip record) async {
    await _service.deletePayslip(id);
    await Helperfunctions.logDelete(
      'Payslip ${record.payslipNumber}',
      record.toJson(),
      page: AppPages.payslip,
    );
  }

  /// Issues payslip to salesman
  Future<void> issuePayslip(String id) async {
    await _service.updateStatus(id, PayslipStatus.issued);
  }

  /// Marks payslip as acknowledged by salesman
  Future<void> acknowledgePayslip(String id) async {
    await _service.updateStatus(id, PayslipStatus.acknowledged);
  }

  /// Marks payslip as paid by dealer
  Future<void> markPaid(String id) async {
    await _service.updateStatus(id, PayslipStatus.paid);
  }

  /// Calculates start (Monday) and end (Sunday) of the week containing [date]
  static ({DateTime start, DateTime end, String label}) getWeekRange(DateTime date) {
    // In Dart DateTime, Monday is 1 and Sunday is 7.
    final monday = DateTime(date.year, date.month, date.day - (date.weekday - 1), 0, 0, 0);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6, 23, 59, 59);

    final label = '${_dateFormat.format(monday)} - ${_dateFormat.format(sunday)}';
    return (start: monday, end: sunday, label: label);
  }

  /// Groups a list of payslips into "Current Payslip" and "Previous Payslips"
  static PayslipGroupedResult groupPayslips(List<Payslip> allPayslips) {
    if (allPayslips.isEmpty) {
      return const PayslipGroupedResult(currentPayslip: null, previousPayslips: []);
    }

    final now = DateTime.now();

    // Look for a payslip within current week first
    Payslip? current;
    final List<Payslip> previous = [];

    for (final p in allPayslips) {
      final pStart = p.periodStart.toDate();
      final pEnd = p.periodEnd.toDate();

      final matchesCurrentWeek = (now.isAfter(pStart) || now.isAtSameMomentAs(pStart)) &&
          (now.isBefore(pEnd) || now.isAtSameMomentAs(pEnd));

      if (matchesCurrentWeek && current == null) {
        current = p;
      } else {
        previous.add(p);
      }
    }

    // If no payslip specifically during current week, feature the newest one as current
    if (current == null && allPayslips.isNotEmpty) {
      current = allPayslips.first;
      previous.remove(current);
    }

    return PayslipGroupedResult(
      currentPayslip: current,
      previousPayslips: previous,
    );
  }
}
