import 'package:cloud_firestore/cloud_firestore.dart';

class Hapistore {
  String storeName;
  String storeAddress;
  String storeContact;

  Hapistore({
    required this.storeName,
    required this.storeAddress,
    required this.storeContact
  });

  static Hapistore empty() => Hapistore(storeName: '', storeAddress: '', storeContact: '');

  Hapistore.fromJson(Map<String, Object?> json) 
  : this(
      storeName: json['storeName']! as String,
      storeAddress: json['storeAddress']! as String,
      storeContact: json['storeContact']! as String,
    );

  factory Hapistore.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document){
    if (document.data() != null){
      final data = document.data();
      return Hapistore(storeName: data?['storeName'], storeAddress: data?['storeAddress'], storeContact: data?['storeContact']);
    }
    else{
      return Hapistore.empty();
    }
  }

  Hapistore copyWith({
    String? storeName,
    String? storeAddress,
    String? storeContact,
    String? storeNameSearch,
  }) {
    return Hapistore(
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeContact: storeContact ?? this.storeContact);
  }

  Map<String,Object?> toJson(){
    return {
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storeContact': storeContact,
    };
  }
}