import 'package:flutter_app/models/delivery.dart';

class BuyingDto {
  final String? storeName;
  final bool? isBuying;
  final int? buyingCount;
  final List<Delivery>? listDeliveries;
  final double? deliveredAmount;

  BuyingDto({this.storeName, this.isBuying, this.buyingCount, this.listDeliveries, this.deliveredAmount});
}
