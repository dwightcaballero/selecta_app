// ignore: constant_identifier_names
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/scanning.dart';

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
    final querySnapshot = await _scanningRef.where('barcode', isEqualTo: barcode).get();
    if (querySnapshot.docs.isNotEmpty) {
      Scanning scanning = querySnapshot.docs.first.data();
      scanning = scanning.copyWith(id: querySnapshot.docs.first.id);
      return scanning;
    } else {
      return null;
    }
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

      // Check if scanned date is within the month
      if (scanning.scannedDate != null) {
        final now = DateTime.now();
        final scannedDate = scanning.scannedDate!.toDate();
        if (scannedDate.year != now.year && scannedDate.month != now.month) {
          scanning = scanning.copyWith(scannedDate: null, scannedBy: '');
        }
      }

      return scanning;
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
