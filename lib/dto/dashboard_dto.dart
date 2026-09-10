class DashboardDTO {
  int buyingCount;
  int nonBuyingCount;
  double buyingThruput;
  int unpaidCreditCount;
  int pendingDeliveryCount;
  int returnedDeliveryCount;

  DashboardDTO({
    required this.buyingCount,
    required this.nonBuyingCount,
    required this.buyingThruput,
    required this.unpaidCreditCount,
    required this.pendingDeliveryCount,
    required this.returnedDeliveryCount,
  });

  static DashboardDTO empty() {
    return DashboardDTO(buyingCount: 0, nonBuyingCount: 0, buyingThruput: 0, unpaidCreditCount: 0, pendingDeliveryCount: 0, returnedDeliveryCount: 0);
  }

  DashboardDTO.fromJson(Map<String, Object?> json)
    : this(
        buyingCount: json['buyingCount']! as int,
        nonBuyingCount: json['nonBuyingCount']! as int,
        buyingThruput: json['buyingThruput']! as double,
        unpaidCreditCount: json['unpaidCreditCount']! as int,
        pendingDeliveryCount: json['pendingDeliveryCount']! as int,
        returnedDeliveryCount: json['returnedDeliveryCount']! as int,
      );

  Map<String, Object?> toJson() {
    return {
      'buyingCount': buyingCount,
      'nonBuyingCount': nonBuyingCount,
      'buyingThruput': buyingThruput,
      'unpaidCreditCount': unpaidCreditCount,
      'pendingDeliveryCount': pendingDeliveryCount,
      'returnedDeliveryCount': returnedDeliveryCount,
    };
  }
}
