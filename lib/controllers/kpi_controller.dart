import 'package:flutter_app/dto/kpi_dto.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';

class KPIController {
  static Future<(List<KPIBuying>, List<KPIBuying>)> getListOfBuyingAndNonBuyingStores() async {
    List<KPIBuying> listBuying = [];
    List<KPIBuying> listNonBuying = [];

    var listHapiStores = await HapiStoreService.getListHapiStores();
    var listDelivery = await DeliveryService.getListDeliveryWithinCurrentMonth();

    for (var store in listHapiStores) {
      var listTransactions = listDelivery.where((delivery) => delivery.storeName.toLowerCase() == store.storeName.toLowerCase());

      if (listTransactions.isNotEmpty) {
        // Get the total delivered amount of all transactions
        double deliveredAmount = 0;
        for (var delivery in listTransactions) {
          deliveredAmount += delivery.cashAmount + delivery.onlineAmount + delivery.creditAmount;
        }

        listBuying.add(KPIBuying(storeName: store.storeName, orderCount: listTransactions.length, deliveredAmount: deliveredAmount));
      } else {
        listNonBuying.add(KPIBuying(storeName: store.storeName, orderCount: 0, deliveredAmount: 0));
      }
    }

    return (listBuying, listNonBuying);
  }
}
