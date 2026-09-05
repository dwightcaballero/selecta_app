import 'package:cloud_firestore/cloud_firestore.dart';

class Dealer {
  String dealerName;

  Dealer({required this.dealerName});

  static Dealer empty() => Dealer(dealerName: '');

  Dealer.fromJson(Map<String, Object?> json)
    : this(dealerName: json['dealerName']! as String);

  factory Dealer.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Dealer(dealerName: data?['dealerName']);
    } else {
      return Dealer.empty();
    }
  }

  Dealer copyWith({String? dealerName}) {
    return Dealer(dealerName: dealerName ?? this.dealerName);
  }

  Map<String, Object?> toJson() {
    return {'dealerName': dealerName};
  }
}
