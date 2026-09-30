import 'package:cloud_firestore/cloud_firestore.dart';

class Configuration {
  Timestamp merchBlitzStartDate;
  Timestamp merchBlitzEndDate;
  bool aiEnabled;
  String geminiApiKey;
  int aiMonthlyRequestLimit;

  // KPI Monthly Targets
  double salesTarget;
  double buyingTargetPercentage;
  double throughputTarget;
  double placementTargetPercentage;
  double scanningTargetPercentage;
  int expansionTarget;

  Configuration({
    required this.merchBlitzStartDate,
    required this.merchBlitzEndDate,
    this.aiEnabled = true,
    this.geminiApiKey = '',
    this.aiMonthlyRequestLimit = 3000,
    this.salesTarget = 1000000.0,
    this.buyingTargetPercentage = 80.0,
    this.throughputTarget = 8000.0,
    this.placementTargetPercentage = 80.0,
    this.scanningTargetPercentage = 100.0,
    this.expansionTarget = 10,
  });

  // Alternate casing accessor for flexibility
  // ignore: non_constant_identifier_names
  Timestamp get MerchiBlitzEndDate => merchBlitzEndDate;
  // ignore: non_constant_identifier_names
  set MerchiBlitzEndDate(Timestamp value) => merchBlitzEndDate = value;

  static Configuration empty() => Configuration(
        merchBlitzStartDate: Timestamp.now(),
        merchBlitzEndDate: Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        aiEnabled: true,
        geminiApiKey: '',
        aiMonthlyRequestLimit: 3000,
        salesTarget: 1000000.0,
        buyingTargetPercentage: 80.0,
        throughputTarget: 8000.0,
        placementTargetPercentage: 80.0,
        scanningTargetPercentage: 100.0,
        expansionTarget: 10,
      );

  Configuration.fromJson(Map<String, Object?> json)
      : this(
          merchBlitzStartDate: (json['merchBlitzStartDate'] is Timestamp)
              ? json['merchBlitzStartDate'] as Timestamp
              : (json['MerchiBlitzStartDate'] is Timestamp)
                  ? json['MerchiBlitzStartDate'] as Timestamp
                  : Timestamp.now(),
          merchBlitzEndDate: (json['merchBlitzEndDate'] is Timestamp)
              ? json['merchBlitzEndDate'] as Timestamp
              : (json['MerchiBlitzEndDate'] is Timestamp)
                  ? json['MerchiBlitzEndDate'] as Timestamp
                  : Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
          aiEnabled: json['aiEnabled'] as bool? ?? true,
          geminiApiKey: json['geminiApiKey'] as String? ?? '',
          aiMonthlyRequestLimit: (json['aiMonthlyRequestLimit'] as num?)?.toInt() ?? 3000,
          salesTarget: (json['salesTarget'] as num?)?.toDouble() ?? 1000000.0,
          buyingTargetPercentage: (json['buyingTargetPercentage'] as num?)?.toDouble() ?? 80.0,
          throughputTarget: (json['throughputTarget'] as num?)?.toDouble() ?? 8000.0,
          placementTargetPercentage: (json['placementTargetPercentage'] as num?)?.toDouble() ?? 80.0,
          scanningTargetPercentage: (json['scanningTargetPercentage'] as num?)?.toDouble() ?? 100.0,
          expansionTarget: (json['expansionTarget'] as num?)?.toInt() ?? 10,
        );

  Configuration copyWith({
    Timestamp? merchBlitzStartDate,
    Timestamp? merchBlitzEndDate,
    bool? aiEnabled,
    String? geminiApiKey,
    int? aiMonthlyRequestLimit,
    double? salesTarget,
    double? buyingTargetPercentage,
    double? throughputTarget,
    double? placementTargetPercentage,
    double? scanningTargetPercentage,
    int? expansionTarget,
  }) {
    return Configuration(
      merchBlitzStartDate: merchBlitzStartDate ?? this.merchBlitzStartDate,
      merchBlitzEndDate: merchBlitzEndDate ?? this.merchBlitzEndDate,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      aiMonthlyRequestLimit: aiMonthlyRequestLimit ?? this.aiMonthlyRequestLimit,
      salesTarget: salesTarget ?? this.salesTarget,
      buyingTargetPercentage: buyingTargetPercentage ?? this.buyingTargetPercentage,
      throughputTarget: throughputTarget ?? this.throughputTarget,
      placementTargetPercentage: placementTargetPercentage ?? this.placementTargetPercentage,
      scanningTargetPercentage: scanningTargetPercentage ?? this.scanningTargetPercentage,
      expansionTarget: expansionTarget ?? this.expansionTarget,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'merchBlitzStartDate': merchBlitzStartDate,
      'merchBlitzEndDate': merchBlitzEndDate,
      'MerchiBlitzEndDate': merchBlitzEndDate,
      'aiEnabled': aiEnabled,
      'geminiApiKey': geminiApiKey,
      'aiMonthlyRequestLimit': aiMonthlyRequestLimit,
      'salesTarget': salesTarget,
      'buyingTargetPercentage': buyingTargetPercentage,
      'throughputTarget': throughputTarget,
      'placementTargetPercentage': placementTargetPercentage,
      'scanningTargetPercentage': scanningTargetPercentage,
      'expansionTarget': expansionTarget,
    };
  }
}
