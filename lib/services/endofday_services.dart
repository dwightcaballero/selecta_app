import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/dto/endofday_dto.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/expenses_services.dart';

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

      endofday.totalorderamount += data[DeliveryModelString.orderAmount];
      endofday.cashamount += data[DeliveryModelString.cashAmount];
      endofday.onlineamount += data[DeliveryModelString.onlineAmount];
      endofday.creditamount += data[DeliveryModelString.creditAmount];
      endofday.returnedAmount += data[DeliveryModelString.returnAmount];
      endofday.totaldeliveredamount +=
          data[DeliveryModelString.cashAmount] + data[DeliveryModelString.onlineAmount] + data[DeliveryModelString.creditAmount];
      endofday.totaldelivery += 1;

      switch (data[DeliveryModelString.transactionStatus]) {
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

    BadOrderService dbBO = BadOrderService();
    endofday.badorderAmount = await dbBO.getTotalBadOrderForSpecificDay(deliveryDate) ?? 0;

    ExpensesService dbXP = ExpensesService();
    endofday.expenseAmount = await dbXP.getTotalExpensesForEndOfDay(deliveryDate) ?? 0;

    BreakdownService dbBD = BreakdownService();
    Breakdown? breakdown = await dbBD.getDocumentsBySpecificDate(deliveryDate);

    if (breakdown != null) {
      endofday.actualcashonhand = breakdown.breakdownAmount;
      endofday.discrepancy = breakdown.discrepancy;
      endofday.bankdeposit = breakdown.bankDepositAmount;
    }

    endofday.expectedcashonhand = endofday.cashamount - endofday.badorderAmount - endofday.expenseAmount;

    return endofday;
  }
}
