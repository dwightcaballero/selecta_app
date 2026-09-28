import 'package:cloud_firestore/cloud_firestore.dart';

class Configuration {
  Timestamp merchBlitzStartDate;
  Timestamp merchBlitzEndDate;
  bool aiEnabled;
  String geminiApiKey;
  int aiMonthlyRequestLimit;

  Configuration({
    required this.merchBlitzStartDate,
    required this.merchBlitzEndDate,
    this.aiEnabled = true,
    this.geminiApiKey = '',
    this.aiMonthlyRequestLimit = 3000,
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
        );

  Configuration copyWith({
    Timestamp? merchBlitzStartDate,
    Timestamp? merchBlitzEndDate,
    bool? aiEnabled,
    String? geminiApiKey,
    int? aiMonthlyRequestLimit,
  }) {
    return Configuration(
      merchBlitzStartDate: merchBlitzStartDate ?? this.merchBlitzStartDate,
      merchBlitzEndDate: merchBlitzEndDate ?? this.merchBlitzEndDate,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      aiMonthlyRequestLimit: aiMonthlyRequestLimit ?? this.aiMonthlyRequestLimit,
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
    };
  }
}
