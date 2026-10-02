import 'dart:io';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<void> writeToInternalFile(String log) async {
  // 1. Log through the centralized error service
  await ErrorLogService.logError(
    action: 'Manual AppLog Write',
    error: log,
  );

  // 2. Also keep the daily log file for legacy access (appending rather than overwriting)
  final directory = await getApplicationDocumentsDirectory();
  String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final file = File('${directory.path}/${formattedDate}_logs.txt');
  await file.writeAsString('$log\n', mode: FileMode.append);
}

Future<File?> readFromFile() async {
  final directory = await getApplicationDocumentsDirectory();
  String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final file = File('${directory.path}/${formattedDate}_logs.txt');
  if (await file.exists()) {
    return file;
  }
  return null;
}
