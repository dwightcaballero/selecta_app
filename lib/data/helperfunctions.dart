import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/transactionlog.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/transactionlog_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

class Helperfunctions {
  static String formatStringAmountForDisplay(String stringAmount) {
    if (stringAmount.isNotEmpty) {
      String cleanAmount = stringAmount.replaceAll(RegExp(r'[^0-9.]'), '');
      double finalAmount = double.tryParse(cleanAmount) ?? 0;

      return NumberFormat('#,##0.00').format(finalAmount);
    }

    return '0.00';
  }

  static String formatDoubleAmountForDisplay(double amount) {
    return NumberFormat.currency(symbol: '₱').format(amount);
  }

  static String formatDoubleAmountForField(double amount) {
    if (amount == 0) return '';
    return NumberFormat('#,##0.00').format(amount);
  }

  static double formatStringAmountToDouble(String stringAmount) {
    String cleanAmount = stringAmount.replaceAll(RegExp(r'[^0-9.]'), '');
    double finalAmount = double.tryParse(cleanAmount) ?? 0;

    return finalAmount;
  }

  static Decimal formatStringAmountToDecimal(String stringAmount) {
    String cleanAmount = stringAmount.replaceAll(RegExp(r'[^0-9.]'), '');
    Decimal finalAmount = Decimal.parse(cleanAmount.isEmpty ? '0' : cleanAmount);

    return finalAmount;
  }

  static String formatStringAmountForEditing(String stringAmount) {
    String cleanAmount = stringAmount.replaceAll(RegExp(r'[^0-9.]'), '');
    double finalAmount = double.tryParse(cleanAmount) ?? 0;

    return finalAmount.toString().replaceAll(RegExp(r'\.0+$'), '');
  }

  static String formatDateForDisplay(DateTime dt) {
    return DateFormat('E, d MMM yyyy').format(dt);
  }

  static String formatTimestampForDisplay(Timestamp ts) {
    return DateFormat('E, d MMM yyyy').format(ts.toDate());
  }

  static DateTime startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static bool isSameWeek(DateTime a, DateTime b) {
    final startA = startOfWeek(a);
    final startB = startOfWeek(b);
    return startA.isAtSameMomentAs(startB);
  }

  static void navigateTo(BuildContext context, dynamic nextPage) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => nextPage));
  }

  static Future<void> navigateThenWait(BuildContext context, dynamic nextPage) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context2) => nextPage));
  }

  static Future<void> deleteImage(BuildContext context, String firestoreURL) async {
    final cleanUrl = firestoreURL.trim();
    if (cleanUrl.isEmpty) return;

    // Evict from local disk cache (`product_image_cache/`) and memory cache
    await CachedProductImage.evictUrl(cleanUrl);

    try {
      Reference storageRef = FirebaseStorage.instance.refFromURL(cleanUrl);
      await storageRef.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found' && context.mounted) {
        ShowMessage.error(context, e.message ?? 'There was an error upon deleting an image.');
      }
    } catch (_) {
      // Ignore non-Firebase Storage URLs
    }
  }

  static Future<String> updateImage(BuildContext context, File? image, String networkImagePath, String savedURLfromDatabase) async {
    String imageFilePath = '';

    // check if there is an existing image saved in the database
    if (savedURLfromDatabase.isNotEmpty) {
      // check if there is a new image uploaded, then delete the old image in the database
      if (image != null) {
        await Helperfunctions.deleteImage(context, savedURLfromDatabase);
        if (context.mounted) {
          imageFilePath = await Helperfunctions.saveImage(context, image);
        }
      } else {
        // if image already exists in database and was not removed by user, don't do anything to existing record
        if (networkImagePath.isNotEmpty) {
          imageFilePath = networkImagePath;
        }
        // if image already exists in database and was removed by user, delete the image in database
        else {
          await Helperfunctions.deleteImage(context, savedURLfromDatabase);
        }
      }
    } else {
      // if there is no existing image, save new image record if user uploaded an image
      if (image != null) {
        imageFilePath = await Helperfunctions.saveImage(context, image);
      }
    }

    return imageFilePath;
  }

  static Future<String> saveImage(BuildContext context, File image) async {
    try {
      final userID = authService.value.currentUser?.uid ?? 'guest';
      final storageRef = FirebaseStorage.instance.ref();
      final fileName = image.path.split('/').last;
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final filePath = '$userID/uploads/$timestamp-$fileName';
      final uploadRef = storageRef.child(filePath);

      await uploadRef.putFile(image);
      return await storageRef.child(filePath).getDownloadURL();
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ShowMessage.error(context, e.message ?? 'There was an error upon uploading an image.');
      }
    }

    return '';
  }

  static Future<String> getImageURL(BuildContext context, String filePath) async {
    try {
      return await FirebaseStorage.instance.ref(filePath).getDownloadURL();
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ShowMessage.error(context, e.message ?? 'There was an error retrieving image data.');
      }
    }

    return '';
  }

  static String getFileNameFromPath(String filepath) {
    return filepath.split('/').last;
  }

  static Future<void> logTransaction(String message, String details, String logAction, {String page = ''}) async {
    Users? user = await KVariables.getUser();
    TransactionLog log;
    if (user != null) {
      log = TransactionLog(
        dealerName: user.dealerName,
        loggedBy: user.username,
        loggedRole: user.role,
        logAction: logAction,
        loggedDate: Timestamp.now(),
        message: message,
        details: details,
        page: page,
      );
    } else {
      log = TransactionLog(
        dealerName: '',
        loggedBy: '',
        loggedRole: '',
        logAction: logAction,
        loggedDate: Timestamp.now(),
        message: message,
        details: details,
        page: page,
      );
    }

    final TransactionLogService db = TransactionLogService();
    await db.addLog(log);
  }

  // audit metadata fields excluded from create/update log details since they're redundant with the log's own loggedBy/loggedDate
  static const List<String> _auditFieldsToSkip = ['createdBy', 'lastUpdatedBy', 'createdDate', 'lastupdatedDate', 'createdPage', 'lastUpdatedPage'];

  static String _formatFieldValue(Object? value) {
    if (value == null) return '(empty)';
    if (value is Timestamp) return formatTimestampForDisplay(value);
    if (value is String) return value.isEmpty ? '(empty)' : value;
    return value.toString();
  }

  static String _formatRecordDetails(Map<String, Object?> data) {
    return data.entries
        .where((entry) => !_auditFieldsToSkip.contains(entry.key))
        .map((entry) => '${entry.key}: ${_formatFieldValue(entry.value)}')
        .join('\n');
  }

  /// Logs the creation of a record, capturing all of its field values.
  static Future<void> logCreate(String identifier, Map<String, Object?> newData, {String page = ''}) async {
    await logTransaction(identifier, _formatRecordDetails(newData), LogAction.create, page: page);
  }

  /// Logs an update to a record, capturing only the fields whose values actually changed.
  static Future<void> logUpdate(String identifier, Map<String, Object?> oldData, Map<String, Object?> newData, {String page = ''}) async {
    final List<String> changes = [];
    for (final key in newData.keys) {
      if (_auditFieldsToSkip.contains(key)) continue;
      final oldValue = oldData[key];
      final newValue = newData[key];
      if (oldValue.toString() != newValue.toString()) {
        changes.add('$key: ${_formatFieldValue(oldValue)} → ${_formatFieldValue(newValue)}');
      }
    }

    await logTransaction(identifier, changes.isEmpty ? 'No field changes detected.' : changes.join('\n'), LogAction.update, page: page);
  }

  /// Logs the deletion of a record, capturing all of its field values at the time of deletion.
  static Future<void> logDelete(String identifier, Map<String, Object?> oldData, {String page = ''}) async {
    await logTransaction(identifier, _formatRecordDetails(oldData), LogAction.delete, page: page);
  }

  static BuildContext? _activeLoadingContext;
  static bool _isLoadingDialogOpen = false;

  static Future<void> showLoading({BuildContext? context, required bool showLoading}) async {
    if (showLoading) {
      if (_isLoadingDialogOpen) return;
      if (context == null || !context.mounted) return;
      _isLoadingDialogOpen = true;

      showDialog<void>(
        context: context,
        barrierDismissible: false, // Prevents closing by tapping outside the dialog
        useRootNavigator: true,
        builder: (BuildContext dialogContext) {
          _activeLoadingContext = dialogContext;
          if (!_isLoadingDialogOpen) {
            // Dismissed before dialog finished building
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            });
          }
          final theme = Theme.of(dialogContext);
          return PopScope(
            canPop: false, // Prevents closing via the physical back button (Flutter 3.12+)
            child: Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator.adaptive(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ).then((_) {
        _isLoadingDialogOpen = false;
        _activeLoadingContext = null;
      });
    } else {
      if (!_isLoadingDialogOpen && _activeLoadingContext == null) return;
      _isLoadingDialogOpen = false;

      final dialogCtx = _activeLoadingContext;
      _activeLoadingContext = null;

      if (dialogCtx != null && dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop();
      }
    }
  }

  static final RegExp _srpRegex = RegExp(
    r'(?:^|[^\w])(?:PHP|SRP:?|[P₱])\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );

  /// Extracts numeric SRP from a product name/description (e.g. "P10", "P105", "₱20", "SRP 25").
  static double? extractSrp(String text) {
    final match = _srpRegex.firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Compares two products by extracted SRP ascending, then alphabetically by name.
  /// If neither has an extracted SRP, falls back to selling price comparison.
  static int compareBySrpAndName({
    required String nameA,
    required double priceA,
    required String nameB,
    required double priceB,
  }) {
    final srpA = extractSrp(nameA);
    final srpB = extractSrp(nameB);

    if (srpA != null && srpB != null) {
      final srpComp = srpA.compareTo(srpB);
      if (srpComp != 0) return srpComp;
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    } else if (srpA != null) {
      return -1;
    } else if (srpB != null) {
      return 1;
    }

    final priceComp = priceA.compareTo(priceB);
    if (priceComp != 0) return priceComp;
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  }

  /// Compares categories ensuring "By Case" comes before "By Piece", followed by other categories.
  static int compareCategoryHierarchy(String catA, String catB) {
    int getRank(String cat) {
      final lower = cat.trim().toLowerCase();
      if (lower == 'by case' || lower.contains('case')) return 0;
      if (lower == 'by piece' || lower.contains('piece')) return 1;
      return 2;
    }
    return getRank(catA).compareTo(getRank(catB));
  }
}
