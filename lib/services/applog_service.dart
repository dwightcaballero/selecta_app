import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<void> writeToInternalFile(String log) async {
  // 1. Get the app's secure documents directory
  final directory = await getApplicationDocumentsDirectory();

  // define the current date
  String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // 2. Define the file path
  final file = File('${directory.path}/${formattedDate}_logs.txt');

  // 3. Write data to the file
  await file.writeAsString(log);
}

Future<File?> readFromFile() async {
  final directory = await getApplicationDocumentsDirectory();

  // define the current date
  String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  return File('${directory.path}/${formattedDate}_logs.txt');
}
