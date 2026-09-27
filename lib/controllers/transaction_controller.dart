import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/transactionlog.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/transactionlog_service.dart';

/// Metrics count for audit transaction logs
class LogCounts {
  final int total;
  final int create;
  final int update;
  final int delete;

  const LogCounts({
    required this.total,
    required this.create,
    required this.update,
    required this.delete,
  });
}

/// Filtered result containing counts and matching logs
class LogFilterResult {
  final LogCounts counts;
  final List<QueryDocumentSnapshot> filteredLogs;

  const LogFilterResult({
    required this.counts,
    required this.filteredLogs,
  });
}

/// Controller responsible for Store Transactions and Audit Transaction Logs
class TransactionController {
  final DeliveryService _deliveryService = DeliveryService();
  final TransactionLogService _logService = TransactionLogService();

  /// Stream of deliveries for a store within a given date range
  Stream<QuerySnapshot> getStoreDeliveriesStream(String storeName, String monthsAgo) {
    return _deliveryService.getListDeliveryByStoreNameAndDateRange(storeName, monthsAgo);
  }

  /// Stream of audit transaction logs for a single calendar day
  Stream<QuerySnapshot> getLogsForDayStream(DateTime date) {
    return _logService.getLogsForDay(date);
  }

  /// Computes the sum of order amounts across delivery documents
  double calculateTotalDeliveriesAmount(List<QueryDocumentSnapshot> docs) {
    double total = 0;
    for (var doc in docs) {
      final delivery = doc.data() as Delivery;
      total += delivery.orderAmount;
    }
    return total;
  }

  /// Filters logs by action category and search terms, and calculates summary counts
  LogFilterResult processLogs({
    required List<QueryDocumentSnapshot> allDocs,
    required String selectedActionFilter,
    required String searchQuery,
  }) {
    int createCount = 0;
    int updateCount = 0;
    int deleteCount = 0;

    final List<QueryDocumentSnapshot> filteredLogs = [];
    final query = searchQuery.trim().toLowerCase();

    for (var doc in allDocs) {
      final log = doc.data() as TransactionLog;

      if (log.logAction == LogAction.create) createCount++;
      if (log.logAction == LogAction.update) updateCount++;
      if (log.logAction == LogAction.delete) deleteCount++;

      final bool matchesAction = selectedActionFilter == 'All' || log.logAction == selectedActionFilter;
      final bool matchesSearch = query.isEmpty ||
          log.message.toLowerCase().contains(query) ||
          log.details.toLowerCase().contains(query) ||
          log.loggedBy.toLowerCase().contains(query) ||
          log.loggedRole.toLowerCase().contains(query) ||
          log.page.toLowerCase().contains(query) ||
          log.dealerName.toLowerCase().contains(query);

      if (matchesAction && matchesSearch) {
        filteredLogs.add(doc);
      }
    }

    return LogFilterResult(
      counts: LogCounts(
        total: allDocs.length,
        create: createCount,
        update: updateCount,
        delete: deleteCount,
      ),
      filteredLogs: filteredLogs,
    );
  }
}
