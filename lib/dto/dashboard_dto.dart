class DashboardDto {
  int buyingCount;
  int nonBuyingCount;
  double buyingThruput;

  DashboardDto({required this.buyingCount, required this.nonBuyingCount, required this.buyingThruput});

  static DashboardDto empty() {
    return DashboardDto(buyingCount: 0, nonBuyingCount: 0, buyingThruput: 0);
  }

  DashboardDto.fromJson(Map<String, Object?> json)
    : this(
        buyingCount: json['buyingCount']! as int,
        nonBuyingCount: json['nonBuyingCount']! as int,
        buyingThruput: json['buyingThruput']! as double,
      );

  Map<String, Object?> toJson() {
    return {'buyingCount': buyingCount, 'nonBuyingCount': nonBuyingCount, 'buyingThruput': buyingThruput};
  }
}
