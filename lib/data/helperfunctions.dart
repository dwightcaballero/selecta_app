import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/transactionlog.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/transactionlog_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

class Helperfunctions {
  static String formatStringAmountForDisplay(String stringAmount) {
    if (stringAmount.isNotEmpty) {
      String cleanAmount = stringAmount.replaceAll(RegExp(r'[^0-9.]'), '');
      double finalAmount = double.tryParse(cleanAmount) ?? 0;

      return NumberFormat.currency(symbol: '₱').format(finalAmount);
    }

    return NumberFormat.currency(symbol: '₱').format(0);
  }

  static String formatDoubleAmountForDisplay(double amount) {
    return NumberFormat.currency(symbol: '₱').format(amount);
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

  static void navigateTo(BuildContext context, dynamic nextPage) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => nextPage));
  }

  static Future<void> navigateThenWait(BuildContext context, dynamic nextPage) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context2) => nextPage));
  }

  static Future<void> deleteImage(BuildContext context, String firestoreURL) async {
    try {
      Reference storageRef = FirebaseStorage.instance.refFromURL(firestoreURL);
      await storageRef.delete();
    } on FirebaseException catch (e) {
      if (context.mounted) {
        ShowMessage.error(context, e.message ?? 'There was an error upon deleting an image.');
      }
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
      final userID = authService.value.currentUser!.uid;
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

  static Future<void> logTransaction(String message, String details, String logAction) async {
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
      );
    }

    final TransactionLogService db = TransactionLogService();
    db.addLog(log);
  }

  static Future<void> showLoading({required BuildContext context, required bool showLoading}) async {
    if (showLoading) {
      showDialog(
        context: context,
        barrierDismissible: false, // Prevents closing by tapping outside the dialog
        builder: (BuildContext context2) {
          return PopScope(
            canPop: false, // Prevents closing via the physical back button (Flutter 3.12+)
            child: AlertDialog(
              backgroundColor: Colors.transparent, // Makes the card invisible
              elevation: 0, // Removes the shadow drop
              surfaceTintColor: Colors.transparent, // Removes the Material 3 tint overlay
              content: Lottie.asset('assets/lotties/loading.json', width: 150, height: 150),
            ),
          );
        },
      );
    } else {
      await Future.delayed(const Duration(milliseconds: 300), () {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      });
    }
  }
}
