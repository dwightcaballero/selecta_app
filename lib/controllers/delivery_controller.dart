import 'dart:io';
import 'package:another_telephony/telephony.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:intl/intl.dart';

/// Aggregated counts by delivery status for summary widgets.
class DeliverySummaryCounts {
  /// Total number of deliveries for the selected date.
  final int all;

  /// Count of successfully delivered records.
  final int delivered;

  /// Count of records pending delivery.
  final int pending;

  /// Count of records that were returned.
  final int returned;

  const DeliverySummaryCounts({
    required this.all,
    required this.delivered,
    required this.pending,
    required this.returned,
  });
}

/// Container bundling fetched placement document ID and placement items for a store.
class PlacementLoadResult {
  /// Existing placement document ID in Firestore, if any.
  final String placementId;

  /// List of placement items with state populated from the database.
  final List<KPlacement> placements;

  const PlacementLoadResult({
    required this.placementId,
    required this.placements,
  });
}

/// Controller managing business logic, computations, validations, and service orchestration
/// for both [DeliveryListPage] and [DeliveryPage].
///
/// By centralizing delivery operations here:
/// - Firebase/Firestore operations are strictly delegated to the appropriate Service classes
///   ([DeliveryService], [PlacementService], [BreakdownService], [HapiStoreService]).
/// - UI views remain clean and focused solely on widget presentation and user interaction.
/// - Calculations (discrepancy, validation, summaries, placement mapping, SMS formatting)
///   are modular, readable, and testable.
class DeliveryController {
  final DeliveryService _deliveryService;
  final PlacementService _placementService;
  final BreakdownService _breakdownService;

  DeliveryController({
    DeliveryService? deliveryService,
    PlacementService? placementService,
    BreakdownService? breakdownService,
  })  : _deliveryService = deliveryService ?? DeliveryService(),
        _placementService = placementService ?? PlacementService(),
        _breakdownService = breakdownService ?? BreakdownService();

  // ==========================================
  // Shared / Role & Breakdown Queries
  // ==========================================

  /// Verifies whether the currently logged-in user possesses dealer privileges.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Checks if a cash breakdown has already been recorded for the specified [date].
  ///
  /// When recorded, salesmen are locked from modifying delivery records for that day.
  Future<bool> checkBreakdownStatus(DateTime date) async {
    final String breakdownId = await _breakdownService.getIDofBreakdown(date);
    return breakdownId.isNotEmpty;
  }

  // ==========================================
  // List Operations (DeliveryListPage)
  // ==========================================

  /// Returns a real-time stream of delivery records for a specific delivery date.
  Stream<QuerySnapshot> getDeliveriesStream(DateTime date) {
    return _deliveryService.getListDeliveryByDate(date);
  }

  /// Fetches the count of returned deliveries from past days that need attention/rescheduling.
  Future<int?> getCountReturnedDeliveriesOnOtherDays() async {
    return await DeliveryService.getCountReturnedDeliveriesOnOtherDays();
  }

  /// Formats the selected date into a friendly navigation label (e.g. "Today, 28 Sep 2026").
  String formatDateLabel(DateTime selectedDate) {
    final today = DateTime.now();
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);

    if (selectedDay == currentDay) {
      return 'Today, ${DateFormat('d MMM yyyy').format(selectedDate)}';
    }
    if (selectedDay == currentDay.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('d MMM').format(selectedDate)}';
    }
    if (selectedDay == currentDay.add(const Duration(days: 1))) {
      return 'Tomorrow, ${DateFormat('d MMM').format(selectedDate)}';
    }
    return DateFormat('EEE, d MMM yyyy').format(selectedDate);
  }

  /// Computes summary counts across all delivery documents for the interactive status tabs.
  DeliverySummaryCounts computeSummaryCounts(List docs) {
    int pending = 0;
    int delivered = 0;
    int returned = 0;

    for (final item in docs) {
      final Delivery delivery = item.data() as Delivery;
      switch (delivery.transactionStatus) {
        case DeliveryStatus.pending:
          pending++;
          break;
        case DeliveryStatus.delivered:
          delivered++;
          break;
        case DeliveryStatus.returned:
          returned++;
          break;
      }
    }

    return DeliverySummaryCounts(
      all: docs.length,
      delivered: delivered,
      pending: pending,
      returned: returned,
    );
  }

  /// Filters delivery document snapshots by selected status tab and search query.
  List filterDeliveries({
    required List docs,
    required String selectedStatus,
    required String searchQuery,
  }) {
    final query = searchQuery.trim().toLowerCase();
    return docs.where((doc) {
      final Delivery delivery = doc.data() as Delivery;
      final matchesStatus = selectedStatus == 'All' || delivery.transactionStatus == selectedStatus;
      final matchesSearch = query.isEmpty || delivery.storeName.toLowerCase().contains(query);
      return matchesStatus && matchesSearch;
    }).toList();
  }

  // ==========================================
  // Detail & Form Operations (DeliveryPage)
  // ==========================================

  /// Computes payment discrepancy (total received payments minus the required order amount).
  ///
  /// Returns `0.0` if balanced, positive if overpaid, negative if underpaid.
  double computeDiscrepancy({
    required double orderAmount,
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
  }) {
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = Helperfunctions.formatStringAmountToDecimal(returnAmount);

    final Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmt;
    final Decimal orderAmt = Decimal.parse(orderAmount.toString());

    return (totalAmount - orderAmt).toDouble();
  }

  /// Calculates total collected payments across cash, online, credit, and return fields.
  double computeTotalCollected({
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
  }) {
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = Helperfunctions.formatStringAmountToDecimal(returnAmount);

    return (cashAmount + onlineAmount + creditAmount + returnAmt).toDouble();
  }

  /// Validates delivery payment breakdown and return remarks before updating.
  ///
  /// Returns a list of validation error messages, or an empty list if valid.
  List<String> validateDeliveryForm({
    required String status,
    required double orderAmount,
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
    required String remarks,
  }) {
    final List<String> listError = [];
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = Helperfunctions.formatStringAmountToDecimal(returnAmount);

    final Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmt;
    final Decimal orderAmt = Decimal.parse(orderAmount.toString());

    if (status == DeliveryStatus.delivered && totalAmount != orderAmt) {
      listError.add('Total amount does not match the order amount!');
    }
    if ((returnAmt != Decimal.zero || status == DeliveryStatus.returned) && remarks.trim().isEmpty) {
      listError.add('Please enter a remark for return details!');
    }

    return listError;
  }

  /// Generates the standard customer confirmation SMS notification body.
  String generateSmsMessage({
    required String storeName,
    required String formattedOrderAmount,
  }) {
    return '[SELECTA DELIVERY]\n\n'
        'Good day $storeName! This is to confirm that your order worth ($formattedOrderAmount) is now pending for delivery.\n\n'
        'Please expect your stocks to arrive in a few hours. Thank you for choosing Selecta Ice Cream. Have a sweet day!';
  }

  /// Sends an SMS notification to the customer store using Telephony.
  Future<void> sendDeliverySms({
    required String storeName,
    required String message,
  }) async {
    try {
      String storeContact = await HapiStoreService.getContactByStoreName(storeName);
      storeContact = storeContact.replaceFirst('09', '+639');

      final Telephony telephony = Telephony.instance;
      final bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

      if (permissionsGranted ?? false) {
        telephony.sendSms(to: storeContact, message: message, isMultipart: true);
      }
    } catch (_) {
      // SMS failures should not block successful transaction persistence
    }
  }

  /// Fetches saved placement data for a store in the current month and maps it to placement items.
  Future<PlacementLoadResult> loadPlacementsForStore(String storeName) async {
    final List<KPlacement> listPlacement = KData.getListPlacement();
    String placementId = '';

    if (storeName.isNotEmpty) {
      final savedPlacement = await _placementService.getPlacementByStoreAndDate(storeName, DateTime.now());
      if (savedPlacement != null) {
        placementId = savedPlacement.id;
        final flags = [
          savedPlacement.cotc1,
          savedPlacement.cotc2,
          savedPlacement.cotc3,
          savedPlacement.cotc4,
          savedPlacement.cotc5,
          savedPlacement.cotc6,
          savedPlacement.cotc7,
          savedPlacement.cotc8,
          savedPlacement.cotc9,
          savedPlacement.cotc10,
          savedPlacement.cotc11,
          savedPlacement.cotc12,
        ];

        for (int i = 0; i < listPlacement.length && i < flags.length; i++) {
          if (flags[i]) {
            listPlacement[i].isPlaced = true;
            listPlacement[i].isPlacedFromDB = true;
          }
        }
      }
    }

    return PlacementLoadResult(
      placementId: placementId,
      placements: listPlacement,
    );
  }

  /// Creates a new delivery record in Firestore, saves corresponding placements,
  /// writes an audit log trail, and optionally sends an SMS notification.
  ///
  /// Returns the newly created [Delivery] model.
  Future<Delivery> createDelivery({
    required BuildContext context,
    required String storeName,
    required String orderAmountText,
    required DateTime selectedDate,
    required File? imageFile,
    required List<KPlacement> placements,
    required String placementId,
    required bool sendText,
    required String smsMessage,
  }) async {
    // 1. Upload receipt/delivery image if present
    String imageFilePath = '';
    if (imageFile != null) {
      imageFilePath = await Helperfunctions.saveImage(context, imageFile);
    }

    final double orderAmount = Helperfunctions.formatStringAmountToDouble(orderAmountText);
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    // 2. Build the Delivery entity
    final newRecord = Delivery(
      storeName: storeName,
      remarks: '',
      transactionStatus: DeliveryStatus.pending,
      imagePath: imageFilePath,
      orderAmount: orderAmount,
      returnAmount: 0,
      creditAmount: 0,
      cashAmount: 0,
      onlineAmount: 0,
      deliveryDate: Timestamp.fromDate(selectedDate),
      creditStatus: CreditStatus.unpaid,
      createdBy: currentUserName,
      lastUpdatedBy: currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.delivery,
      lastUpdatedPage: AppPages.delivery,
    );

    // 3. Persist delivery via Service
    await _deliveryService.addDelivery(newRecord);

    // 4. Save placement progress
    final placement = Placement.fromFlags(
      storeName: newRecord.storeName,
      deliveryDate: newRecord.deliveryDate!,
      flags: placements.map((placement) => placement.isPlaced).toList(),
      id: placementId,
    );
    placement.progressCount = placements.where((placement) => placement.isPlaced).length;
    placement.isFinished = placement.progressCount == 12;
    await _placementService.savePlacement(placement);

    // 5. Write audit trail
    await Helperfunctions.logCreate(storeName, newRecord.toJson(), page: AppPages.delivery);

    // 6. Optional customer SMS notification
    if (sendText && smsMessage.isNotEmpty) {
      await sendDeliverySms(storeName: storeName, message: smsMessage);
    }

    return newRecord;
  }

  /// Updates an existing delivery record with new amounts, status, and remarks.
  ///
  /// Uploads/updates receipt images, persists changes through [DeliveryService],
  /// and writes an update audit log trail.
  Future<Delivery> updateDelivery({
    required BuildContext context,
    required String deliveryId,
    required Delivery currentDelivery,
    required String storeName,
    required String status,
    required String remarks,
    required String orderAmountText,
    required String cashAmountText,
    required String onlineAmountText,
    required String creditAmountText,
    required String returnAmountText,
    required File? imageFile,
    required String networkImagePath,
  }) async {
    double returnAmount = 0;
    double creditAmount = 0;
    double onlineAmount = 0;
    double cashAmount = 0;
    String finalRemarks = remarks;
    double finalOrderAmount = currentDelivery.orderAmount;

    switch (status) {
      case DeliveryStatus.pending:
        finalOrderAmount = Helperfunctions.formatStringAmountToDouble(orderAmountText);
        finalRemarks = '';
        break;

      case DeliveryStatus.delivered:
        returnAmount = Helperfunctions.formatStringAmountToDouble(returnAmountText);
        creditAmount = Helperfunctions.formatStringAmountToDouble(creditAmountText);
        onlineAmount = Helperfunctions.formatStringAmountToDouble(onlineAmountText);
        cashAmount = Helperfunctions.formatStringAmountToDouble(cashAmountText);
        break;

      case DeliveryStatus.returned:
        returnAmount = currentDelivery.orderAmount;
        break;
      default:
    }

    // Update image
    final String imageFilePath = await Helperfunctions.updateImage(
      context,
      imageFile,
      networkImagePath,
      currentDelivery.imagePath,
    );

    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    final updatedDelivery = currentDelivery.copyWith(
      storeName: storeName,
      remarks: finalRemarks,
      transactionStatus: status,
      imagePath: imageFilePath,
      orderAmount: finalOrderAmount,
      returnAmount: returnAmount,
      creditAmount: creditAmount,
      cashAmount: cashAmount,
      onlineAmount: onlineAmount,
      deliveryDate: currentDelivery.deliveryDate,
      createdBy: currentDelivery.createdBy,
      lastUpdatedBy: currentUserName,
      createdDate: currentDelivery.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: currentDelivery.createdPage,
      lastUpdatedPage: AppPages.delivery,
    );

    // Persist via Service
    await _deliveryService.updateDelivery(deliveryId, updatedDelivery);

    // Audit log
    await Helperfunctions.logUpdate(
      storeName,
      currentDelivery.toJson(),
      updatedDelivery.toJson(),
      page: AppPages.delivery,
    );

    return updatedDelivery;
  }

  /// Deletes a delivery record and its associated uploaded image from storage.
  Future<void> deleteDelivery({
    required BuildContext context,
    required String deliveryId,
    required Delivery delivery,
  }) async {
    if (delivery.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, delivery.imagePath);
    }
    _deliveryService.deleteDelivery(deliveryId);

    await Helperfunctions.logDelete(delivery.storeName, delivery.toJson(), page: AppPages.delivery);
  }
}
