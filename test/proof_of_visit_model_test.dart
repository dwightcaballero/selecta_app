import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';

void main() {
  group('ProofOfVisit Model Unit Tests', () {
    test('ProofOfVisit serializes to JSON and deserializes correctly', () {
      final now = Timestamp.now();
      final visit = ProofOfVisit(
        id: 'visit_123',
        storeName: 'Aling Maria Sari-Sari Store',
        visitDate: now,
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/selecta.appspot.com/o/visit_123.jpg',
        takenBy: 'Juan Dela Cruz',
        createdAt: now,
        notes: 'Restocked 12 Magnum bars. Freezer running at -18C.',
      );

      final json = visit.toJson();
      expect(json['id'], 'visit_123');
      expect(json['storeName'], 'Aling Maria Sari-Sari Store');
      expect(json['takenBy'], 'Juan Dela Cruz');
      expect(json['notes'], contains('Restocked 12 Magnum'));

      final reconstructed = ProofOfVisit.fromJson(json, id: 'visit_123');
      expect(reconstructed.id, 'visit_123');
      expect(reconstructed.storeName, 'Aling Maria Sari-Sari Store');
      expect(reconstructed.takenBy, 'Juan Dela Cruz');
      expect(reconstructed.notes, contains('Freezer running at -18C'));
    });

    test('ProofOfVisit.empty provides safe fallbacks', () {
      final empty = ProofOfVisit.empty();
      expect(empty.id, '');
      expect(empty.storeName, '');
      expect(empty.imageUrl, '');
      expect(empty.takenBy, '');
      expect(empty.notes, '');
    });

    test('ProofOfVisit.copyWith updates specified fields only', () {
      final now = Timestamp.now();
      final original = ProofOfVisit(
        id: 'pov_1',
        storeName: 'Store A',
        visitDate: now,
        imageUrl: 'url_1',
        takenBy: 'Agent 1',
        notes: 'Initial note',
      );

      final updated = original.copyWith(notes: 'Updated note after manager review', takenBy: 'Agent 2');
      expect(updated.id, 'pov_1');
      expect(updated.storeName, 'Store A');
      expect(updated.takenBy, 'Agent 2');
      expect(updated.notes, 'Updated note after manager review');
    });
  });
}
