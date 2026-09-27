import 'package:cloud_firestore/cloud_firestore.dart';

class Configuration {
  Timestamp merchBlitzStartDate;
  Timestamp merchBlitzEndDate;

  Configuration({required this.merchBlitzStartDate, required this.merchBlitzEndDate});

  // Alternate casing accessor for flexibility
  // ignore: non_constant_identifier_names
  Timestamp get MerchiBlitzEndDate => merchBlitzEndDate;
  // ignore: non_constant_identifier_names
  set MerchiBlitzEndDate(Timestamp value) => merchBlitzEndDate = value;

  static Configuration empty() =>
      Configuration(merchBlitzStartDate: Timestamp.now(), merchBlitzEndDate: Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))));

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
      );

  Configuration copyWith({Timestamp? merchBlitzStartDate, Timestamp? merchBlitzEndDate}) {
    return Configuration(
      merchBlitzStartDate: merchBlitzStartDate ?? this.merchBlitzStartDate,
      merchBlitzEndDate: merchBlitzEndDate ?? this.merchBlitzEndDate,
    );
  }

  Map<String, Object?> toJson() {
    return {'merchBlitzStartDate': merchBlitzStartDate, 'merchBlitzEndDate': merchBlitzEndDate, 'MerchiBlitzEndDate': merchBlitzEndDate};
  }
}
