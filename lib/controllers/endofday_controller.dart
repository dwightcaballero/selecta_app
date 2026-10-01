import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/endofday_dto.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/services/endofday_services.dart';

/// Combined data snapshot for a single day's end-of-day reconciliation
class EndOfDaySnapshot {
  final EndOfDayDTO endOfDayData;
  final Breakdown breakdown;
  final String breakdownId;
  final bool isDealer;

  const EndOfDaySnapshot({
    required this.endOfDayData,
    required this.breakdown,
    required this.breakdownId,
    required this.isDealer,
  });
}

/// Subtotals for individual denominations
class BreakdownTotal {
  double total1000 = 0;
  double total500 = 0;
  double total200 = 0;
  double total100 = 0;
  double total50 = 0;
  double totalB20 = 0;
  double totalC20 = 0;
  double total10 = 0;
  double total5 = 0;
  double total1 = 0;
  double totalCent = 0;
}

/// Calculation results of bill/coin breakdown
class RecomputeResult {
  final BreakdownTotal breakdownTotal;
  final double breakdownAmount;
  final double discrepancy;

  const RecomputeResult({
    required this.breakdownTotal,
    required this.breakdownAmount,
    required this.discrepancy,
  });
}

/// Controller responsible for End of Day reconciliations,
/// cash breakdown calculation, verification, and audit logging.
class EndOfDayController {
  final EndofdayServices _endOfDayService = EndofdayServices();
  final BreakdownService _breakdownService = BreakdownService();

  /// Checks if the active user is a dealer
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Current user display name
  String get currentUserName {
    return authService.value.currentUser?.displayName ?? 'User';
  }

  /// Fetches complete reconciliation snapshot for a target date
  Future<EndOfDaySnapshot> fetchEndOfDayData(DateTime date) async {
    final isDealer = await checkIsDealer();
    final endOfDayData = await _endOfDayService.getListDeliveryForEndOfDay(date);
    var breakdown = await _breakdownService.getDocumentsBySpecificDate(date) ?? Breakdown.empty();
    final breakdownId = await _breakdownService.getIDofBreakdown(date);

    breakdown.breakdownDate = Timestamp.fromDate(date);
    breakdown.expectedAmount = endOfDayData.expectedcashonhand;

    return EndOfDaySnapshot(
      endOfDayData: endOfDayData,
      breakdown: breakdown,
      breakdownId: breakdownId,
      isDealer: isDealer,
    );
  }

  /// Validates whether a day's transactions are ready for cash breakdown
  void validateBeforeBreakdown({
    required EndOfDayDTO endOfDayData,
    required String breakdownId,
  }) {
    if (endOfDayData.totaldelivery == 0 && breakdownId.isEmpty) {
      throw Exception('No deliveries recorded for this date');
    }
    if (endOfDayData.pendingstatus > 0) {
      throw Exception('There should be no transaction that is pending for delivery');
    }
  }

  /// Computes denomination subtotals, grand total, and discrepancy against expected cash
  RecomputeResult recompute({
    required bool withBankDeposit,
    required double bankDepositAmount,
    required int b1000,
    required int b500,
    required int b200,
    required int b100,
    required int b50,
    required int b20,
    required int c20,
    required int c10,
    required int c5,
    required int c1,
    required int cent,
    required double expectedAmount,
  }) {
    final breakdownTotal = BreakdownTotal();
    breakdownTotal.total1000 = b1000 * 1000.0;
    breakdownTotal.total500 = b500 * 500.0;
    breakdownTotal.total200 = b200 * 200.0;
    breakdownTotal.total100 = b100 * 100.0;
    breakdownTotal.total50 = b50 * 50.0;
    breakdownTotal.totalB20 = b20 * 20.0;
    breakdownTotal.totalC20 = c20 * 20.0;
    breakdownTotal.total10 = c10 * 10.0;
    breakdownTotal.total5 = c5 * 5.0;
    breakdownTotal.total1 = c1 * 1.0;
    breakdownTotal.totalCent = cent * 0.01;

    final double breakdownAmount =
        breakdownTotal.total1000 +
        breakdownTotal.total500 +
        breakdownTotal.total200 +
        breakdownTotal.total100 +
        breakdownTotal.total50 +
        breakdownTotal.totalB20 +
        breakdownTotal.totalC20 +
        breakdownTotal.total10 +
        breakdownTotal.total5 +
        breakdownTotal.total1 +
        breakdownTotal.totalCent;

    final effectiveBankDeposit = withBankDeposit ? bankDepositAmount : 0.0;
    final double discrepancy = double.parse(((effectiveBankDeposit + breakdownAmount) - expectedAmount).toStringAsFixed(2));

    return RecomputeResult(
      breakdownTotal: breakdownTotal,
      breakdownAmount: breakdownAmount,
      discrepancy: discrepancy,
    );
  }

  /// Toggles dealer verification status and creates an audit log
  Future<void> toggleVerification({
    required String breakdownId,
    required Breakdown currentRecord,
    required bool newStatus,
  }) async {
    final updatedRecord = currentRecord.copyWith(
      isVerifiedByDealer: newStatus,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.breakdown,
    );

    _breakdownService.updateBreakdown(breakdownId, updatedRecord);
    await Helperfunctions.logUpdate(
      Helperfunctions.formatTimestampForDisplay(updatedRecord.breakdownDate),
      currentRecord.toJson(),
      updatedRecord.toJson(),
      page: AppPages.breakdown,
    );
  }

  /// Creates a new breakdown record and writes an audit log
  Future<void> saveBreakdown({
    required Breakdown record,
  }) async {
    _breakdownService.addBreakdown(record);
    await Helperfunctions.logCreate(
      Helperfunctions.formatTimestampForDisplay(record.breakdownDate),
      record.toJson(),
      page: AppPages.breakdown,
    );
  }

  /// Updates an existing breakdown record and writes an audit log
  Future<void> updateBreakdown({
    required String breakdownId,
    required Breakdown originalRecord,
    required Breakdown updatedRecord,
  }) async {
    _breakdownService.updateBreakdown(breakdownId, updatedRecord);
    await Helperfunctions.logUpdate(
      Helperfunctions.formatTimestampForDisplay(updatedRecord.breakdownDate),
      originalRecord.toJson(),
      updatedRecord.toJson(),
      page: AppPages.breakdown,
    );
  }
}
