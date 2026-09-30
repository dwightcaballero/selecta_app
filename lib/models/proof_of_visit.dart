import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model representing a photographic Proof of Visit captured during a PJP store visit.
class ProofOfVisit {
  final String id;
  final String storeName;
  final Timestamp visitDate;
  final String imageUrl;
  final String takenBy;
  final Timestamp createdAt;
  final String notes;

  ProofOfVisit({
    this.id = '',
    required this.storeName,
    required this.visitDate,
    required this.imageUrl,
    this.takenBy = '',
    Timestamp? createdAt,
    this.notes = '',
  }) : createdAt = createdAt ?? Timestamp.now();

  static ProofOfVisit empty() => ProofOfVisit(
        storeName: '',
        visitDate: Timestamp.now(),
        imageUrl: '',
        takenBy: '',
        createdAt: Timestamp.now(),
        notes: '',
      );

  ProofOfVisit.fromJson(Map<String, Object?> json, {String id = ''})
      : this(
          id: id.isNotEmpty ? id : (json['id'] as String? ?? '').trim(),
          storeName: (json['storeName'] as String? ?? '').trim(),
          visitDate: json['visitDate'] as Timestamp? ?? Timestamp.now(),
          imageUrl: (json['imageUrl'] as String? ?? '').trim(),
          takenBy: (json['takenBy'] as String? ?? '').trim(),
          createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
          notes: (json['notes'] as String? ?? '').trim(),
        );

  factory ProofOfVisit.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (data != null) {
      return ProofOfVisit.fromJson(data, id: document.id);
    } else {
      return ProofOfVisit.empty();
    }
  }

  ProofOfVisit copyWith({
    String? id,
    String? storeName,
    Timestamp? visitDate,
    String? imageUrl,
    String? takenBy,
    Timestamp? createdAt,
    String? notes,
  }) {
    return ProofOfVisit(
      id: id ?? this.id,
      storeName: storeName ?? this.storeName,
      visitDate: visitDate ?? this.visitDate,
      imageUrl: imageUrl ?? this.imageUrl,
      takenBy: takenBy ?? this.takenBy,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'storeName': storeName,
      'visitDate': visitDate,
      'imageUrl': imageUrl,
      'takenBy': takenBy,
      'createdAt': createdAt,
      'notes': notes,
    };
  }
}
