import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/scanning.dart';

// ignore: constant_identifier_names
const String SCANNING_COLLECTION_REF = 'scanning';

class ScanningServices {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Scanning> _scanningRef;

  ScanningServices() {
    _scanningRef = _firestore
        .collection(SCANNING_COLLECTION_REF)
        .withConverter<Scanning>(
          fromFirestore: (snapshots, _) => Scanning.fromJson(snapshots.data()!),
          toFirestore: (scanning, _) => scanning.toJson(),
        );
  }

  /// Normalizes scanning status so scans from prior months reset to notScanned in the new month.
  static Scanning normalizeMonthlyScanning(Scanning scanning) {
    if (scanning.status == ScanningStatus.pullout || scanning.status == ScanningStatus.unassigned) {
      return scanning;
    }
    final now = DateTime.now();
    if (scanning.scannedDate != null) {
      final date = scanning.scannedDate!.toDate();
      final isCurrentMonth = date.year == now.year && date.month == now.month;
      if (!isCurrentMonth) {
        return scanning.copyWith(
          clearScannedDate: true,
          scannedBy: '',
          status: ScanningStatus.notScanned,
          imageUrl: '',
        );
      }
    } else if (scanning.status == ScanningStatus.scanned || scanning.status == ScanningStatus.pending) {
      return scanning.copyWith(status: ScanningStatus.notScanned, imageUrl: '', clearScannedDate: true);
    }
    return scanning;
  }

  // Save scanning record if it doesnt exist in the database. Else, update the existing record.
  Future<void> saveScanning(Scanning scanning) async {
    if (scanning.id.isEmpty) {
      await _scanningRef.add(scanning);
    } else {
      await _scanningRef.doc(scanning.id).update(scanning.toJson());
    }
  }

  // Get scanning record by barcode
  Future<Scanning?> getScanningByBarcode(String barcode) async {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return null;
    final querySnapshot = await _scanningRef.where('barcode', isEqualTo: trimmedBarcode).get();
    if (querySnapshot.docs.isNotEmpty) {
      Scanning scanning = querySnapshot.docs.first.data();
      scanning = scanning.copyWith(id: querySnapshot.docs.first.id);
      return normalizeMonthlyScanning(scanning);
    } else {
      return null;
    }
  }

  // Get scanning records for a specific store
  Future<List<Scanning>> getScanningsByStoreName(String storeName) async {
    final snapshot = await _scanningRef.where('storeName', isEqualTo: storeName).get();
    return snapshot.docs.map((doc) => normalizeMonthlyScanning(doc.data().copyWith(id: doc.id))).toList();
  }

  // Get all scanning records
  static Future<List<Scanning>> getAllScannings() async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection(SCANNING_COLLECTION_REF)
        .withConverter<Scanning>(
          fromFirestore: (snapshots, _) => Scanning.fromJson(snapshots.data()!),
          toFirestore: (scanning, _) => scanning.toJson(),
        )
        .get();
    return querySnapshot.docs.map((doc) {
      Scanning scanning = doc.data();
      scanning = scanning.copyWith(id: doc.id);
      return normalizeMonthlyScanning(scanning);
    }).toList();
  }

  void addScanning(Scanning scanning) {
    _scanningRef.add(scanning);
  }

  void updateScanning(String scanningID, Scanning scanning) {
    _scanningRef.doc(scanningID).update(scanning.toJson());
  }

  Future<void> deleteScanning(String scanningID) {
    return _scanningRef.doc(scanningID).delete();
  }
}
