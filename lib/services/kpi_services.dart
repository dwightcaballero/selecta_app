// class KpiServices {
//   getListOfBuyingAndNonBuyingStores() async {
//     List<BuyingDto> listBuyingStores = [];

//     var listStores = await HapiStoreService().getListHapiStores();
//     var listDelivery = await DeliveryService().getListDeliveryWithinCurrentMonth();

//     for (var store in listStores) {
//       var listTransactions = listDelivery.where((delivery) => delivery.storeName.toLowerCase() == store.storeName.toLowerCase());

//       if (listTransactions.isNotEmpty) {
//         // Get the total delivered amount of all transactions
//         double deliveredAmount = 0;
//         for (var delivery in listTransactions) {
//           deliveredAmount += delivery.cashAmount + delivery.onlineAmount + delivery.creditAmount;
//         }

//         listBuyingStores.add(
//           BuyingDto(storeName: store.storeName, isBuying: true, buyingCount: listTransactions.length, deliveredAmount: deliveredAmount),
//         );
//       } else {
//         listBuyingStores.add(BuyingDto(storeName: store.storeName, isBuying: false, buyingCount: 0, deliveredAmount: 0));
//       }
//     }

//     return listBuyingStores;
//   }
// }
