import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/dto/endofday_dto.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/expenses_services.dart';

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

      endofday.totalorderamount += data[DeliveryModelString.orderAmount];
      endofday.cashamount += data[DeliveryModelString.cashAmount];
      endofday.onlineamount += data[DeliveryModelString.onlineAmount];
      endofday.creditamount += data[DeliveryModelString.creditAmount];
      endofday.returnedAmount += data[DeliveryModelString.returnAmount];
      final deliveredPortion = (data[DeliveryModelString.cashAmount] as num? ?? 0).toDouble() +
          (data[DeliveryModelString.onlineAmount] as num? ?? 0).toDouble() +
          (data[DeliveryModelString.creditAmount] as num? ?? 0).toDouble();

      final orderType = data[DeliveryModelString.orderType] as String? ?? OrderType.preSell;
      if (orderType == OrderType.vanSell) {
        endofday.vanSellCount += 1;
        endofday.vanSellAmount += deliveredPortion;
      } else {
        endofday.preSellCount += 1;
        endofday.preSellAmount += deliveredPortion;
      }

      endofday.totaldeliveredamount +=
          data[DeliveryModelString.cashAmount] + data[DeliveryModelString.onlineAmount] + data[DeliveryModelString.creditAmount];
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
    }

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

    return endofday;
  }
}
