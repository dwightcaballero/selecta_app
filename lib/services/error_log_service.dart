import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:package_info_plus/package_info_plus.dart';

/// Data model representing a structured error log entry.
class ErrorLogItem {
  final String id;
  final DateTime timestamp;
  final String page;
  final String action;
  final String error;
  final String? stackTrace;
  final String? userEmail;
  final String? userRole;
  final String platform;
  final String? appVersion;
  final Map<String, dynamic>? extraData;
  bool isUploaded;

  ErrorLogItem({
    required this.id,
    required this.timestamp,
    required this.page,
    required this.action,
    required this.error,
    this.stackTrace,
    this.userEmail,
    this.userRole,
    required this.platform,
    this.appVersion,
    this.extraData,
    this.isUploaded = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'loggedDate': Timestamp.fromDate(timestamp),
      'page': page,
      'action': action,
      'error': error,
      'stackTrace': stackTrace,
      'userEmail': userEmail,
      'userRole': userRole,
      'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      if (extraData != null) 'extraData': extraData,
      'isUploaded': isUploaded,
    };
  }

  factory ErrorLogItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    if (json['timestamp'] is String) {
      parsedTime = DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now();
    } else if (json['loggedDate'] is Timestamp) {
      parsedTime = (json['loggedDate'] as Timestamp).toDate();
    } else {
      parsedTime = DateTime.now();
    }

    return ErrorLogItem(
      id: json['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
      timestamp: parsedTime,
      page: json['page'] as String? ?? 'Unknown',
      action: json['action'] as String? ?? 'General Operation',
      error: json['error'] as String? ?? 'Unknown error',
      stackTrace: json['stackTrace'] as String?,
      userEmail: json['userEmail'] as String?,
      userRole: json['userRole'] as String?,
      platform: json['platform'] as String? ?? Platform.operatingSystem,
      appVersion: json['appVersion'] as String?,
      extraData: json['extraData'] is Map ? Map<String, dynamic>.from(json['extraData'] as Map) : null,
      isUploaded: json['isUploaded'] as bool? ?? false,
    );
  }
}

/// Centralized service handling error capturing, secure local sandbox buffering,
/// automatic/manual Firestore synchronization, and formatted AI diagnostic exports.
class ErrorLogService {
  static const String collectionRef = 'error_logs';
  static const String _localLogFileName = 'error_logs_queue.json';

  static String _currentPage = 'AppInit';
  static String? _cachedAppVersion;

  /// Returns the current active screen/page name.
  static String get currentPage => _currentPage;

  /// Updates the current active screen/page name.
  static void setCurrentPage(String page) {
    if (page.isNotEmpty) {
      _currentPage = page;
    }
  }

  /// Retrieves and caches the running application version string (e.g. v1.0.0+24).
  static Future<String> getAppVersion() async {
    if (_cachedAppVersion != null && _cachedAppVersion!.isNotEmpty) {
      return _cachedAppVersion!;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = 'v${info.version}+${info.buildNumber}';
    } catch (_) {
      _cachedAppVersion = 'v1.0.0+24';
    }
    return _cachedAppVersion!;
  }

  /// Helper to get the private application documents file for error queueing.
  static Future<File> _getLocalLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_localLogFileName');
  }

  /// Reads all cached log items from the internal sandboxed file.
  static Future<List<ErrorLogItem>> _readLocalLogs() async {
    try {
      final file = await _getLocalLogFile();
      if (!await file.exists()) {
        return [];
      }
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return [];

      final dynamic decoded = jsonDecode(contents);
      if (decoded is List) {
        return decoded
            .map((item) => ErrorLogItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error reading local error logs: $e');
      return [];
    }
  }

  /// Writes the given list of error log items to the internal sandboxed file.
  static Future<void> _writeLocalLogs(List<ErrorLogItem> items) async {
    try {
      final file = await _getLocalLogFile();
      final jsonList = items.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error persisting local error logs: $e');
    }
  }

  /// Records an exception with active screen, intent/action, stack trace, and user metadata.
  /// Automatically stores locally and attempts a silent background upload to Firestore.
  static Future<void> logError({
    required String action,
    required dynamic error,
    dynamic stackTrace,
    String? page,
    Map<String, dynamic>? extraData,
  }) async {
    final targetPage = page ?? _currentPage;
    final now = DateTime.now();
    final logId = 'err_${now.millisecondsSinceEpoch}_${now.microsecond}';

    String? userEmail;
    String? userRole;
    String? currentVersion;

    try {
      currentVersion = await getAppVersion();
    } catch (_) {
      currentVersion = _cachedAppVersion;
    }

    try {
      final user = await KVariables.getUser();
      userEmail = user?.email ?? FirebaseAuth.instance.currentUser?.email;
      userRole = user?.role;
    } catch (_) {
      userEmail = FirebaseAuth.instance.currentUser?.email;
    }

    final item = ErrorLogItem(
      id: logId,
      timestamp: now,
      page: targetPage,
      action: action,
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      userEmail: userEmail,
      userRole: userRole,
      platform: Platform.operatingSystem,
      appVersion: currentVersion,
      extraData: extraData,
      isUploaded: false,
    );

    debugPrint('[ErrorLogService] Logged error in "$targetPage" during "$action": $error');

    // 1. Persist to local sandbox queue
    final logs = await _readLocalLogs();
    logs.add(item);
    // Keep max 200 items in local buffer to prevent file bloat
    if (logs.length > 200) {
      logs.removeRange(0, logs.length - 200);
    }
    await _writeLocalLogs(logs);

    // 2. Attempt silent background sync to Cloud Firestore
    _syncSingleLogSilently(item);
  }

  /// Executes an asynchronous block guarded by structured error logging.
  /// Ideal for critical user interactions, saves, and network calls.
  static Future<T?> runGuarded<T>({
    required String action,
    String? page,
    required Future<T> Function() task,
    Future<T?> Function(dynamic error, StackTrace stackTrace)? onError,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      return await task();
    } catch (e, s) {
      await logError(
        action: action,
        error: e,
        stackTrace: s,
        page: page,
        extraData: extraData,
      );
      if (onError != null) {
        return await onError(e, s);
      }
      return null;
    }
  }

  /// Silently uploads an error item to Firestore without throwing.
  static Future<void> _syncSingleLogSilently(ErrorLogItem item) async {
    try {
      await FirebaseFirestore.instance.collection(collectionRef).doc(item.id).set(item.toJson());
      // Mark as uploaded in local queue
      final logs = await _readLocalLogs();
      final index = logs.indexWhere((l) => l.id == item.id);
      if (index != -1) {
        logs[index].isUploaded = true;
        await _writeLocalLogs(logs);
      }
    } catch (e) {
      // Offline or network error - remains pending for next batch sync
      debugPrint('[ErrorLogService] Silent upload deferred: $e');
    }
  }

  /// Uploads all pending (unuploaded) logs to Cloud Firestore in a batch write.
  /// Returns the count of logs successfully uploaded.
  static Future<int> uploadPendingLogs() async {
    try {
      final logs = await _readLocalLogs();
      final pendingLogs = logs.where((l) => !l.isUploaded).toList();

      if (pendingLogs.isEmpty) {
        return 0;
      }

      final firestore = FirebaseFirestore.instance;
      // Commit in chunks of 400 (Firestore limit is 500 operations per batch)
      const chunkSize = 400;
      int uploadedCount = 0;

      for (var i = 0; i < pendingLogs.length; i += chunkSize) {
        final chunk = pendingLogs.sublist(
          i,
          i + chunkSize > pendingLogs.length ? pendingLogs.length : i + chunkSize,
        );
        final batch = firestore.batch();

        for (final item in chunk) {
          final docRef = firestore.collection(collectionRef).doc(item.id);
          batch.set(docRef, item.toJson(), SetOptions(merge: true));
        }

        await batch.commit();
        uploadedCount += chunk.length;
      }

      // Mark uploaded items in local file
      for (final item in pendingLogs) {
        item.isUploaded = true;
      }
      await _writeLocalLogs(logs);

      return uploadedCount;
    } catch (e) {
      debugPrint('[ErrorLogService] Batch upload failed: $e');
      rethrow;
    }
  }

  /// Returns the count of pending unuploaded error logs stored on the device.
  static Future<int> getPendingLogCount() async {
    final logs = await _readLocalLogs();
    return logs.where((l) => !l.isUploaded).length;
  }

  /// Stream of recent error logs from Cloud Firestore, sorted by timestamp descending.
  static Stream<List<ErrorLogItem>> streamFirestoreLogs({int limit = 100}) {
    return FirebaseFirestore.instance
        .collection(collectionRef)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ErrorLogItem.fromJson(data);
      }).toList();
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    });
  }

  /// Deletes a specific error log document from Cloud Firestore.
  static Future<void> deleteFirestoreLog(String id) async {
    try {
      await FirebaseFirestore.instance.collection(collectionRef).doc(id).delete();
    } catch (e) {
      debugPrint('[ErrorLogService] Failed to delete Firestore log $id: $e');
      rethrow;
    }
  }

  /// Clears all error log documents from Cloud Firestore.
  static Future<int> clearAllFirestoreLogs() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(collectionRef).get();
      if (snapshot.docs.isEmpty) return 0;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('[ErrorLogService] Failed to clear all Firestore logs: $e');
      rethrow;
    }
  }

  /// Returns all local error logs currently queued on this device.
  static Future<List<ErrorLogItem>> getLocalLogs() async {
    return _readLocalLogs();
  }

  /// Formats any list of error log items into a clean, diagnostic report string.
  static String formatLogsAsText(List<ErrorLogItem> logs, {String title = 'DIAGNOSTIC ERROR LOGS REPORT'}) {
    if (logs.isEmpty) {
      return 'No error logs recorded.';
    }

    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    buffer.writeln('========================================================');
    buffer.writeln('SELECTA APP - $title');
    buffer.writeln('Generated: ${dateFormat.format(DateTime.now())}');
    buffer.writeln('Total Log Entries: ${logs.length}');
    buffer.writeln('========================================================\n');

    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      buffer.writeln('--- [ENTRY #${i + 1}] ------------------------------------------');
      buffer.writeln('Timestamp  : ${dateFormat.format(log.timestamp)}');
      buffer.writeln('Page / View: ${log.page}');
      buffer.writeln('User Action: ${log.action}');
      buffer.writeln('User Info  : ${log.userEmail ?? "Unknown"} (${log.userRole ?? "N/A"})');
      buffer.writeln('Platform   : ${log.platform}');
      buffer.writeln('Uploaded   : ${log.isUploaded ? "Yes (Synced to Firestore)" : "Pending upload"}');
      if (log.extraData != null && log.extraData!.isNotEmpty) {
        buffer.writeln('Extra Data : ${jsonEncode(log.extraData)}');
      }
      buffer.writeln('Error      : ${log.error}');
      if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
        buffer.writeln('Stack Trace:');
        buffer.writeln(log.stackTrace);
      }
      buffer.writeln('');
    }

    buffer.writeln('=================== END OF LOG REPORT ===================');
    return buffer.toString();
  }

  /// Formats all locally queued error logs into a diagnostic report.
  static Future<String> exportLogsAsText() async {
    final logs = await _readLocalLogs();
    return formatLogsAsText(logs, title: 'LOCAL DEVICE ERROR LOGS REPORT');
  }

  /// Clears all local log records.
  static Future<void> clearLocalLogs() async {
    try {
      final file = await _getLocalLogFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error clearing local logs: $e');
    }
  }
}

/// Custom RouteObserver that updates the active page inside [ErrorLogService].
class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  void _extractAndSetPageName(Route<dynamic> route) {
    String? name = route.settings.name;
    if (name == null || name.isEmpty) {
      // Derive name from route widget or string
      name = route.runtimeType.toString();
    }
    ErrorLogService.setCurrentPage(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _extractAndSetPageName(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _extractAndSetPageName(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _extractAndSetPageName(previousRoute);
    }
  }
}
