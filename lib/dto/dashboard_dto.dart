class DashboardDTO {
  int buyingCount;
  int nonBuyingCount;
  int totalHapiStores;
  double buyingThruput;
  int unpaidCreditCount;
  int pendingDeliveryCount;
  int returnedDeliveryCount;
  double totalBuyingSales;
  int totaltransactionCount;
  int overpaymentCount;
  double totalInvoiceAmount;
  int totalPlacementCount;
  int totalExpansionCount;
  int totalScanCount;
  int totalNotScannedCount;
  int pendingPjpCount;

  DashboardDTO({
    required this.buyingCount,
    required this.nonBuyingCount,
    required this.totalHapiStores,
    required this.buyingThruput,
    required this.unpaidCreditCount,
    required this.pendingDeliveryCount,
    required this.returnedDeliveryCount,
    required this.totalBuyingSales,
    required this.totaltransactionCount,
    required this.overpaymentCount,
    required this.totalInvoiceAmount,
    required this.totalPlacementCount,
    required this.totalExpansionCount,
    required this.totalScanCount,
    required this.totalNotScannedCount,
    this.pendingPjpCount = 0,
  });

  static DashboardDTO empty() {
    return DashboardDTO(
      buyingCount: 0,
      nonBuyingCount: 0,
      totalHapiStores: 0,
      buyingThruput: 0,
      unpaidCreditCount: 0,
      pendingDeliveryCount: 0,
      returnedDeliveryCount: 0,
      totalBuyingSales: 0,
      totaltransactionCount: 0,
      overpaymentCount: 0,
      totalInvoiceAmount: 0,
      totalPlacementCount: 0,
      totalExpansionCount: 0,
      totalScanCount: 0,
      totalNotScannedCount: 0,
      pendingPjpCount: 0,
    );
  }

  DashboardDTO.fromJson(Map<String, Object?> json)
    : this(
        buyingCount: json['buyingCount']! as int,
        nonBuyingCount: json['nonBuyingCount']! as int,
        totalHapiStores: json['totalHapiStores']! as int,
        buyingThruput: json['buyingThruput']! as double,
        unpaidCreditCount: json['unpaidCreditCount']! as int,
        pendingDeliveryCount: json['pendingDeliveryCount']! as int,
        returnedDeliveryCount: json['returnedDeliveryCount']! as int,
        totalBuyingSales: json['totalBuyingSales']! as double,
        totaltransactionCount: json['totaltransactionCount']! as int,
        overpaymentCount: json['overpaymentCount']! as int,
        totalInvoiceAmount: json['totalInvoiceAmount']! as double,
        totalPlacementCount: json['totalPlacementCount']! as int,
        totalExpansionCount: json['totalExpansionCount']! as int,
        totalScanCount: json['totalScanCount']! as int,
        totalNotScannedCount: json['totalNotScannedCount']! as int,
        pendingPjpCount: (json['pendingPjpCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toJson() {
    return {
      'buyingCount': buyingCount,
      'nonBuyingCount': nonBuyingCount,
      'totalHapiStores': totalHapiStores,
      'buyingThruput': buyingThruput,
      'unpaidCreditCount': unpaidCreditCount,
      'pendingDeliveryCount': pendingDeliveryCount,
      'returnedDeliveryCount': returnedDeliveryCount,
      'totalBuyingSales': totalBuyingSales,
      'totaltransactionCount': totaltransactionCount,
      'overpaymentCount': overpaymentCount,
      'totalInvoiceAmount': totalInvoiceAmount,
      'totalPlacementCount': totalPlacementCount,
      'totalExpansionCount': totalExpansionCount,
      'totalScanCount': totalScanCount,
      'totalNotScannedCount': totalNotScannedCount,
      'pendingPjpCount': pendingPjpCount,
    };
  }
}
