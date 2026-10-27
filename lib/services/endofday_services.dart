import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/dto/endofday_dto.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/expenses_services.dart';
import 'package:selecta_ops/services/return_proof_service.dart';
import 'package:selecta_ops/services/van_load_service.dart';

class EndofdayServices {
  Future<EndOfDayDTO> getListDeliveryForEndOfDay(DateTime deliveryDate) async {
    // check dates
    final startOfDay = DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day, 0, 0, 0);

    final endOfDay = DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day, 23, 59, 59);

    EndOfDayDTO endofday = EndOfDayDTO.empty();
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    final List<MapEntry<String, Delivery>> allDeliveries = [];

    // Loop through the snapshot query objects
    for (var doc in snapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      final status = data[DeliveryModelString.transactionStatus];

      if (status == DeliveryStatus.voided) {
        continue;
      }
      // Exclude orders pending picklist: they are still in order booking/picking queue
      // (for today or future dates) and have not yet been dispatched for delivery.
      if (status == DeliveryStatus.pendingPicklist) {
        endofday.pendingPicklistStatus += 1;
        continue;
      }

      final double cash = (data[DeliveryModelString.cashAmount] as num? ?? 0).toDouble();
      final double online = (data[DeliveryModelString.onlineAmount] as num? ?? 0).toDouble();
      final double credit = (data[DeliveryModelString.creditAmount] as num? ?? 0).toDouble();
      final double orderAmt = (data[DeliveryModelString.orderAmount] as num? ?? 0).toDouble();
      final double returnAmt = (data[DeliveryModelString.returnAmount] as num? ?? 0).toDouble();

      endofday.totalorderamount += orderAmt;
      endofday.cashamount += cash;
      endofday.onlineamount += online;
      endofday.creditamount += credit;
      endofday.returnedAmount += returnAmt;
      final deliveredPortion = cash + online + credit;

      final orderType = data[DeliveryModelString.orderType] as String? ?? OrderType.preSell;
      if (orderType == OrderType.vanSell) {
        endofday.vanSellCount += 1;
        endofday.vanSellAmount += (deliveredPortion > 0 ? deliveredPortion : orderAmt);
        endofday.vanSellCashAmount += cash;
        endofday.vanSellOnlineAmount += online;
        endofday.vanSellCreditAmount += credit;
      } else {
        endofday.preSellCount += 1;
        endofday.preSellAmount += (deliveredPortion > 0 ? deliveredPortion : orderAmt);
        endofday.preSellCashAmount += cash;
        endofday.preSellOnlineAmount += online;
        endofday.preSellCreditAmount += credit;
      }

      endofday.totaldeliveredamount += deliveredPortion;
      endofday.totaldelivery += 1;

      switch (status) {
        case DeliveryStatus.pending:
          endofday.pendingstatus += 1;
          break;
        case DeliveryStatus.delivered:
          endofday.deliveredstatus += 1;
          break;
        case DeliveryStatus.returned:
          endofday.returnedstatus += 1;
          break;
        default:
      }

      try {
        allDeliveries.add(MapEntry(doc.id, Delivery.fromJson(data)));
      } catch (_) {}
    }

    // Process return proof gate for stores with returns
    try {
      final config = await ConfigurationService().getConfiguration();
      final returnProofService = ReturnProofService();

      final Map<String, List<MapEntry<String, Delivery>>> returnsByStore = {};
      for (final entry in allDeliveries) {
        final delivery = entry.value;
        if (ReturnProofService.deliveryHasReturns(delivery) &&
            ReturnProofService.isDeliverySubjectToGate(delivery, config.returnProofEnabledFrom)) {
          returnsByStore.putIfAbsent(delivery.storeName.trim(), () => []).add(entry);
        }
      }

      if (returnsByStore.isNotEmpty) {
        final List<StoreReturnProofSummary> summaries = [];
        bool hasUnconfirmed = false;

        for (final storeEntry in returnsByStore.entries) {
          final storeName = storeEntry.key;
          final deliveriesWithIds = storeEntry.value;

          int storeRetQty = 0;
          double storeRetAmt = 0;
          for (final d in deliveriesWithIds) {
            final del = d.value;
            final isFull = del.transactionStatus == DeliveryStatus.returned;
            for (final item in del.items) {
              final q = item.returnedQuantity > 0 ? item.returnedQuantity : (isFull ? item.pickedQuantity : 0);
              storeRetQty += q;
              storeRetAmt += (q * item.sellingPrice);
            }
          }

          final proof = await returnProofService.getProofForStoreAndDate(storeName, deliveryDate);
          if (proof != null) {
            // Re-validate if returns changed
            await returnProofService.checkAndInvalidateIfReturnsChanged(
              proof: proof,
              deliveriesWithIds: deliveriesWithIds,
            );
          }

          final refreshedProof = await returnProofService.getProofForStoreAndDate(storeName, deliveryDate);
          final status = refreshedProof?.status ?? ReturnProofStatus.none;

          final summary = StoreReturnProofSummary(
            storeName: storeName,
            status: status,
            deliveriesWithIds: deliveriesWithIds,
            totalReturnedQty: storeRetQty,
            totalReturnedAmount: storeRetAmt,
            proof: refreshedProof,
            rejectReason: refreshedProof?.rejectReason,
          );
          summaries.add(summary);

          if (!summary.isSatisfied) {
            hasUnconfirmed = true;
          }
        }

        endofday.returnStores = summaries;
        endofday.hasUnconfirmedReturnProof = hasUnconfirmed;
      }
    } catch (_) {}

    ExpensesService dbXP = ExpensesService();
    final dayExpenses = await dbXP.getExpensesForEndOfDay(deliveryDate);

    double salesmanExp = 0.0;
    double dealerCashExp = 0.0;
    double dealerOnlineExp = 0.0;

    for (final exp in dayExpenses) {
      if (exp.isSalesmanExpense) {
        salesmanExp += exp.expenseAmount;
      } else {
        if (exp.isOnline) {
          dealerOnlineExp += exp.expenseAmount;
        } else {
          dealerCashExp += exp.expenseAmount;
        }
      }
    }

    endofday.salesmanExpenseAmount = salesmanExp;
    endofday.dealerExpenseCashAmount = dealerCashExp;
    endofday.dealerExpenseOnlineAmount = dealerOnlineExp;
    endofday.dealerExpenseAmount = dealerCashExp + dealerOnlineExp;
    // Only cash expenses (salesman cash + dealer cash) are deducted from expected cash on hand:
    endofday.expenseAmount = salesmanExp + dealerCashExp;

    BreakdownService dbBD = BreakdownService();
    Breakdown? breakdown = await dbBD.getDocumentsBySpecificDate(deliveryDate);

    if (breakdown != null) {
      endofday.actualcashonhand = breakdown.breakdownAmount;
      endofday.discrepancy = breakdown.discrepancy;
      endofday.bankdeposit = breakdown.bankDepositAmount;
    }

    endofday.expectedcashonhand = endofday.cashamount - endofday.expenseAmount;

    try {
      final vanLoadService = VanLoadService();
      endofday.vanLoad = await vanLoadService.getVanLoadForDate(deliveryDate);
    } catch (_) {}

    return endofday;
  }
}
