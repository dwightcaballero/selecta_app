import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/dto/profit_loss_dto.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/services/badorder_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/expenses_services.dart';

enum ProfitLossPeriod {
  today('Today'),
  thisWeek('This Week'),
  thisMonth('This Month'),
  thisQuarter('This Quarter'),
  thisYear('This Year'),
  custom('Custom');

  final String label;
  const ProfitLossPeriod(this.label);
}

class ProfitLossDateRange {
  final DateTime start;
  final DateTime end;
  final ProfitLossPeriod period;

  const ProfitLossDateRange({
    required this.start,
    required this.end,
    required this.period,
  });

  static ProfitLossDateRange forPeriod(ProfitLossPeriod period, {DateTime? customStart, DateTime? customEnd}) {
    final now = DateTime.now();

    switch (period) {
      case ProfitLossPeriod.today:
        final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return ProfitLossDateRange(start: start, end: end, period: period);

      case ProfitLossPeriod.thisWeek:
        // Week starts on Monday (Dart weekday: Monday=1, Sunday=7)
        final monday = DateTime(now.year, now.month, now.day, 0, 0, 0).subtract(Duration(days: now.weekday - 1));
        final sunday = DateTime(monday.year, monday.month, monday.day + 6, 23, 59, 59);
        return ProfitLossDateRange(start: monday, end: sunday, period: period);

      case ProfitLossPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1, 0, 0, 0);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return ProfitLossDateRange(start: start, end: end, period: period);

      case ProfitLossPeriod.thisQuarter:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, qStartMonth, 1, 0, 0, 0);
        final end = DateTime(now.year, qStartMonth + 3, 0, 23, 59, 59);
        return ProfitLossDateRange(start: start, end: end, period: period);

      case ProfitLossPeriod.thisYear:
        final start = DateTime(now.year, 1, 1, 0, 0, 0);
        final end = DateTime(now.year, 12, 31, 23, 59, 59);
        return ProfitLossDateRange(start: start, end: end, period: period);

      case ProfitLossPeriod.custom:
        final start = customStart != null
            ? DateTime(customStart.year, customStart.month, customStart.day, 0, 0, 0)
            : DateTime(now.year, now.month, 1, 0, 0, 0);
        final end = customEnd != null
            ? DateTime(customEnd.year, customEnd.month, customEnd.day, 23, 59, 59)
            : DateTime(now.year, now.month, now.day, 23, 59, 59);
        return ProfitLossDateRange(start: start, end: end, period: period);
    }
  }
}

class ProfitLossController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Main computation method: fetches deliveries, expenses, bad orders within
  /// the date range and computes the full Profit & Loss statement.
  Future<ProfitLossDTO> computeProfitLoss(ProfitLossDateRange range) async {
    final start = range.start;
    final end = range.end;

    // 1. Fetch delivered deliveries within range
    final deliveries = await _fetchDeliveredOrders(start, end);

    // 2. Fetch expenses within range and filter to Dealer expenses only
    // Salesman expenses (e.g. driver snacks) are excluded from business analytics
    final allExpenses = await _fetchExpenses(start, end);
    final expenses = allExpenses.where((exp) => exp.isDealerExpense).toList();

    // 3. Fetch bad orders within range
    final badOrders = await _fetchBadOrders(start, end);

    // 4. Compute delivery revenue and COGS
    double grossRevenue = 0.0;
    double returnDeductions = 0.0;
    double netRevenue = 0.0;
    double grossCOGS = 0.0;
    double returnCOGSDeductions = 0.0;
    double netCOGS = 0.0;

    int totalItemsSold = 0;
    int totalItemsReturned = 0;

    for (final d in deliveries) {
      if (d.items.isNotEmpty) {
        double dGrossRev = 0.0;
        double dReturnDed = 0.0;
        double dGrossCOGS = 0.0;
        double dReturnCOGS = 0.0;

        for (final item in d.items) {
          dGrossRev += item.lineTotal;
          dReturnDed += item.returnedLineTotal;
          dGrossCOGS += item.lineCost;
          dReturnCOGS += (item.returnedQuantity * item.buyingPrice);
          totalItemsSold += item.deliveredQuantity;
          totalItemsReturned += item.returnedQuantity;
        }

        grossRevenue += dGrossRev;
        returnDeductions += dReturnDed;
        grossCOGS += dGrossCOGS;
        returnCOGSDeductions += dReturnCOGS;
        netRevenue += (dGrossRev - dReturnDed);
        netCOGS += (dGrossCOGS - dReturnCOGS);
      } else {
        final collected = d.cashAmount + d.onlineAmount + d.creditAmount;
        final ret = d.returnAmount;
        final gross = d.originalOrderAmount ?? (d.orderAmount + ret);
        final net = collected > 0 ? collected : d.orderAmount;

        grossRevenue += gross;
        returnDeductions += ret;
        netRevenue += net;
      }
    }

    // 5. Operating Expenses
    double totalExpenses = 0.0;
    for (final exp in expenses) {
      totalExpenses += exp.expenseAmount;
    }

    // 6. Bad Order Losses
    double totalBadOrders = 0.0;
    for (final bo in badOrders) {
      final amt = bo.badorderAmount > 0 ? bo.badorderAmount : bo.totalAmount;
      totalBadOrders += amt;
    }

    // 7. Profit calculations
    final grossProfit = netRevenue - netCOGS;
    final grossMarginPercent = netRevenue > 0 ? (grossProfit / netRevenue) * 100 : 0.0;

    final totalOperatingCosts = totalExpenses + totalBadOrders;
    final netProfit = grossProfit - totalOperatingCosts;
    final netMarginPercent = netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0.0;

    final totalDeliveries = deliveries.length;
    final averageOrderValue = totalDeliveries > 0 ? (netRevenue / totalDeliveries) : 0.0;

    // 8. Build trend points for chart
    final trendPoints = _buildTrendPoints(
      range: range,
      deliveries: deliveries,
      expenses: expenses,
      badOrders: badOrders,
    );

    return ProfitLossDTO(
      periodStart: start,
      periodEnd: end,
      periodLabel: range.period.label,
      grossRevenue: grossRevenue,
      returnDeductions: returnDeductions,
      netRevenue: netRevenue,
      grossCOGS: grossCOGS,
      returnCOGSDeductions: returnCOGSDeductions,
      netCOGS: netCOGS,
      grossProfit: grossProfit,
      grossMarginPercent: grossMarginPercent,
      totalExpenses: totalExpenses,
      totalBadOrders: totalBadOrders,
      totalOperatingCosts: totalOperatingCosts,
      netProfit: netProfit,
      netMarginPercent: netMarginPercent,
      totalDeliveries: totalDeliveries,
      totalItemsSold: totalItemsSold,
      totalItemsReturned: totalItemsReturned,
      totalExpensesCount: expenses.length,
      totalBadOrdersCount: badOrders.length,
      averageOrderValue: averageOrderValue,
      trendPoints: trendPoints,
    );
  }

  /// Fetches delivered orders within [start] and [end].
  /// Uses a bounded date query on deliveryDate, falling back to client-side
  /// transactionStatus filter to ensure compatibility without requiring compound indexes.
  Future<List<Delivery>> _fetchDeliveredOrders(DateTime start, DateTime end) async {
    try {
      final snapshot = await _firestore
          .collection(DELIVERY_COLLECTION_REF)
          .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      return snapshot.docs
          .map((doc) => Delivery.fromJson(doc.data()))
          .where((d) => d.transactionStatus == DeliveryStatus.delivered)
          .toList();
    } catch (_) {
      // Secondary fallback in case deliveryDate query fails or has missing index
      try {
        final snapshot = await _firestore
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.delivered)
            .get();

        return snapshot.docs
            .map((doc) => Delivery.fromJson(doc.data()))
            .where((d) {
              final date = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
              return !date.isBefore(start) && !date.isAfter(end);
            })
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  /// Fetches operational expenses within [start] and [end].
  Future<List<Expenses>> _fetchExpenses(DateTime start, DateTime end) async {
    try {
      final snapshot = await _firestore
          .collection(EXPENSES_COLLECTION_REF)
          .where('expenseDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('expenseDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      return snapshot.docs.map((doc) => Expenses.fromJson(doc.data())).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches bad order records within [start] and [end].
  Future<List<BadOrder>> _fetchBadOrders(DateTime start, DateTime end) async {
    try {
      final snapshot = await _firestore
          .collection(BADORDER_COLLECTION_REF)
          .where('badorderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('badorderDate', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      return snapshot.docs.map((doc) => BadOrder.fromJson(doc.data(), doc.id)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Builds trend points grouped appropriately based on range duration.
  List<ProfitLossTrendPoint> _buildTrendPoints({
    required ProfitLossDateRange range,
    required List<Delivery> deliveries,
    required List<Expenses> expenses,
    required List<BadOrder> badOrders,
  }) {
    final start = range.start;
    final end = range.end;
    final durationDays = end.difference(start).inDays + 1;

    if (range.period == ProfitLossPeriod.today || durationDays <= 1) {
      return _buildHourlyTrendPoints(range, deliveries, expenses, badOrders);
    } else if (range.period == ProfitLossPeriod.thisWeek || durationDays <= 7) {
      return _buildDailyTrendPoints(range, deliveries, expenses, badOrders, days: 7);
    } else if (range.period == ProfitLossPeriod.thisMonth || durationDays <= 31) {
      return _buildDailyTrendPoints(range, deliveries, expenses, badOrders, days: durationDays);
    } else if (range.period == ProfitLossPeriod.thisYear || durationDays > 92) {
      return _buildMonthlyTrendPoints(range, deliveries, expenses, badOrders);
    } else {
      // Default / Quarter / multi-week custom: weekly aggregation
      return _buildWeeklyTrendPoints(range, deliveries, expenses, badOrders);
    }
  }

  /// Intraday hourly trend points (grouped in 2-hour blocks from 6:00 to 20:00).
  List<ProfitLossTrendPoint> _buildHourlyTrendPoints(
    ProfitLossDateRange range,
    List<Delivery> deliveries,
    List<Expenses> expenses,
    List<BadOrder> badOrders,
  ) {
    // 8 slots: 6AM, 8AM, 10AM, 12PM, 2PM, 4PM, 6PM, 8PM+
    final slotHours = [6, 8, 10, 12, 14, 16, 18, 20];
    final slotLabels = ['6 AM', '8 AM', '10 AM', '12 PM', '2 PM', '4 PM', '6 PM', '8 PM'];

    final revenueAcc = List<double>.filled(slotHours.length, 0.0);
    final cogsAcc = List<double>.filled(slotHours.length, 0.0);
    final expensesAcc = List<double>.filled(slotHours.length, 0.0);
    final badOrdersAcc = List<double>.filled(slotHours.length, 0.0);
    final deliveryCountAcc = List<int>.filled(slotHours.length, 0);

    int getSlotIndex(DateTime dt) {
      final hour = dt.hour;
      for (int i = slotHours.length - 1; i >= 0; i--) {
        if (hour >= slotHours[i]) return i;
      }
      return 0;
    }

    for (final d in deliveries) {
      final dt = d.deliveryDate?.toDate() ?? d.lastupdatedDate.toDate();
      final idx = getSlotIndex(dt);
      final netRev = d.items.isNotEmpty
          ? d.items.fold<double>(0.0, (acc, item) => acc + item.deliveredLineTotal)
          : (d.cashAmount + d.onlineAmount + d.creditAmount);
      final netCg = d.items.isNotEmpty
          ? d.items.fold<double>(0.0, (acc, item) => acc + (item.deliveredQuantity * item.buyingPrice))
          : 0.0;

      revenueAcc[idx] += netRev;
      cogsAcc[idx] += netCg;
      deliveryCountAcc[idx] += 1;
    }

    for (final exp in expenses) {
      final idx = getSlotIndex(exp.expenseDate.toDate());
      expensesAcc[idx] += exp.expenseAmount;
    }

    for (final bo in badOrders) {
      final idx = getSlotIndex(bo.badorderDate.toDate());
      final amt = bo.badorderAmount > 0 ? bo.badorderAmount : bo.totalAmount;
      badOrdersAcc[idx] += amt;
    }

    final points = <ProfitLossTrendPoint>[];
    for (int i = 0; i < slotHours.length; i++) {
      final pointDate = DateTime(range.start.year, range.start.month, range.start.day, slotHours[i]);
      final cost = cogsAcc[i] + expensesAcc[i] + badOrdersAcc[i];
      points.add(
        ProfitLossTrendPoint(
          date: pointDate,
          label: slotLabels[i],
          revenue: revenueAcc[i],
          cogs: cogsAcc[i],
          expenses: expensesAcc[i],
          badOrders: badOrdersAcc[i],
          cost: cost,
          profit: revenueAcc[i] - cost,
          deliveryCount: deliveryCountAcc[i],
        ),
      );
    }

    return points;
  }

  /// Daily trend points for weeks and months.
  List<ProfitLossTrendPoint> _buildDailyTrendPoints(
    ProfitLossDateRange range,
    List<Delivery> deliveries,
    List<Expenses> expenses,
    List<BadOrder> badOrders, {
    required int days,
  }) {
    final Map<String, int> dayIndexMap = {};
    final points = <ProfitLossTrendPoint>[];

    final revenueAcc = List<double>.filled(days, 0.0);
    final cogsAcc = List<double>.filled(days, 0.0);
    final expensesAcc = List<double>.filled(days, 0.0);
    final badOrdersAcc = List<double>.filled(days, 0.0);
    final deliveryCountAcc = List<int>.filled(days, 0);

    for (int i = 0; i < days; i++) {
      final date = DateTime(range.start.year, range.start.month, range.start.day + i);
      final key = DateFormat('yyyy-MM-dd').format(date);
      dayIndexMap[key] = i;
    }

    for (final d in deliveries) {
      final date = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
      final key = DateFormat('yyyy-MM-dd').format(date);
      final idx = dayIndexMap[key];
      if (idx != null) {
        final netRev = d.items.isNotEmpty
            ? d.items.fold<double>(0.0, (acc, item) => acc + item.deliveredLineTotal)
            : (d.cashAmount + d.onlineAmount + d.creditAmount);
        final netCg = d.items.isNotEmpty
            ? d.items.fold<double>(0.0, (acc, item) => acc + (item.deliveredQuantity * item.buyingPrice))
            : 0.0;

        revenueAcc[idx] += netRev;
        cogsAcc[idx] += netCg;
        deliveryCountAcc[idx] += 1;
      }
    }

    for (final exp in expenses) {
      final key = DateFormat('yyyy-MM-dd').format(exp.expenseDate.toDate());
      final idx = dayIndexMap[key];
      if (idx != null) {
        expensesAcc[idx] += exp.expenseAmount;
      }
    }

    for (final bo in badOrders) {
      final key = DateFormat('yyyy-MM-dd').format(bo.badorderDate.toDate());
      final idx = dayIndexMap[key];
      if (idx != null) {
        final amt = bo.badorderAmount > 0 ? bo.badorderAmount : bo.totalAmount;
        badOrdersAcc[idx] += amt;
      }
    }

    for (int i = 0; i < days; i++) {
      final date = DateTime(range.start.year, range.start.month, range.start.day + i);
      final label = days <= 7 ? DateFormat('E').format(date) : DateFormat('M/d').format(date);
      final cost = cogsAcc[i] + expensesAcc[i] + badOrdersAcc[i];

      points.add(
        ProfitLossTrendPoint(
          date: date,
          label: label,
          revenue: revenueAcc[i],
          cogs: cogsAcc[i],
          expenses: expensesAcc[i],
          badOrders: badOrdersAcc[i],
          cost: cost,
          profit: revenueAcc[i] - cost,
          deliveryCount: deliveryCountAcc[i],
        ),
      );
    }

    return points;
  }

  /// Weekly trend points for quarters or ranges from 32 to 92 days.
  List<ProfitLossTrendPoint> _buildWeeklyTrendPoints(
    ProfitLossDateRange range,
    List<Delivery> deliveries,
    List<Expenses> expenses,
    List<BadOrder> badOrders,
  ) {
    final points = <ProfitLossTrendPoint>[];
    DateTime current = DateTime(range.start.year, range.start.month, range.start.day);
    int weekNum = 1;

    while (!current.isAfter(range.end)) {
      final weekStart = current;
      DateTime weekEnd = current.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      if (weekEnd.isAfter(range.end)) weekEnd = range.end;

      double wRev = 0.0;
      double wCogs = 0.0;
      double wExp = 0.0;
      double wBo = 0.0;
      int wDelCount = 0;

      for (final d in deliveries) {
        final date = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
        if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
          final netRev = d.items.isNotEmpty
              ? d.items.fold<double>(0.0, (acc, item) => acc + item.deliveredLineTotal)
              : (d.cashAmount + d.onlineAmount + d.creditAmount);
          final netCg = d.items.isNotEmpty
              ? d.items.fold<double>(0.0, (acc, item) => acc + (item.deliveredQuantity * item.buyingPrice))
              : 0.0;
          wRev += netRev;
          wCogs += netCg;
          wDelCount += 1;
        }
      }

      for (final exp in expenses) {
        final date = exp.expenseDate.toDate();
        if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
          wExp += exp.expenseAmount;
        }
      }

      for (final bo in badOrders) {
        final date = bo.badorderDate.toDate();
        if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
          final amt = bo.badorderAmount > 0 ? bo.badorderAmount : bo.totalAmount;
          wBo += amt;
        }
      }

      final cost = wCogs + wExp + wBo;
      points.add(
        ProfitLossTrendPoint(
          date: weekStart,
          label: 'W$weekNum',
          revenue: wRev,
          cogs: wCogs,
          expenses: wExp,
          badOrders: wBo,
          cost: cost,
          profit: wRev - cost,
          deliveryCount: wDelCount,
        ),
      );

      weekNum++;
      current = current.add(const Duration(days: 7));
    }

    return points;
  }

  /// Monthly trend points for annual / full-year ranges.
  List<ProfitLossTrendPoint> _buildMonthlyTrendPoints(
    ProfitLossDateRange range,
    List<Delivery> deliveries,
    List<Expenses> expenses,
    List<BadOrder> badOrders,
  ) {
    final points = <ProfitLossTrendPoint>[];
    final year = range.start.year;

    for (int month = 1; month <= 12; month++) {
      final monthStart = DateTime(year, month, 1, 0, 0, 0);
      final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);

      if (monthStart.isAfter(range.end) || monthEnd.isBefore(range.start)) {
        continue;
      }

      double mRev = 0.0;
      double mCogs = 0.0;
      double mExp = 0.0;
      double mBo = 0.0;
      int mDelCount = 0;

      for (final d in deliveries) {
        final date = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
        if (!date.isBefore(monthStart) && !date.isAfter(monthEnd)) {
          final netRev = d.items.isNotEmpty
              ? d.items.fold<double>(0.0, (acc, item) => acc + item.deliveredLineTotal)
              : (d.cashAmount + d.onlineAmount + d.creditAmount);
          final netCg = d.items.isNotEmpty
              ? d.items.fold<double>(0.0, (acc, item) => acc + (item.deliveredQuantity * item.buyingPrice))
              : 0.0;
          mRev += netRev;
          mCogs += netCg;
          mDelCount += 1;
        }
      }

      for (final exp in expenses) {
        final date = exp.expenseDate.toDate();
        if (!date.isBefore(monthStart) && !date.isAfter(monthEnd)) {
          mExp += exp.expenseAmount;
        }
      }

      for (final bo in badOrders) {
        final date = bo.badorderDate.toDate();
        if (!date.isBefore(monthStart) && !date.isAfter(monthEnd)) {
          final amt = bo.badorderAmount > 0 ? bo.badorderAmount : bo.totalAmount;
          mBo += amt;
        }
      }

      final cost = mCogs + mExp + mBo;
      points.add(
        ProfitLossTrendPoint(
          date: monthStart,
          label: DateFormat('MMM').format(monthStart),
          revenue: mRev,
          cogs: mCogs,
          expenses: mExp,
          badOrders: mBo,
          cost: cost,
          profit: mRev - cost,
          deliveryCount: mDelCount,
        ),
      );
    }

    return points;
  }
}
