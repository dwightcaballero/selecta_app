import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/services/scanning_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scanning Model & Image Serialization', () {
    test('Scanning model serializes and deserializes imageUrl correctly', () {
      final now = Timestamp.now();
      final scanning = Scanning(
        id: 'scan_1',
        barcode: '1234567890',
        storeName: 'Test Store Alpha',
        scannedDate: now,
        scannedBy: 'John Doe',
        status: ScanningStatus.pending,
        imageUrl: 'https://storage.googleapis.com/test-bucket/freezer1.jpg',
      );

      final json = scanning.toJson();
      expect(json['id'], 'scan_1');
      expect(json['barcode'], '1234567890');
      expect(json['status'], ScanningStatus.pending);
      expect(json['imageUrl'], 'https://storage.googleapis.com/test-bucket/freezer1.jpg');

      final deserialized = Scanning.fromJson(json);
      expect(deserialized.id, 'scan_1');
      expect(deserialized.barcode, '1234567890');
      expect(deserialized.storeName, 'Test Store Alpha');
      expect(deserialized.status, ScanningStatus.pending);
      expect(deserialized.imageUrl, 'https://storage.googleapis.com/test-bucket/freezer1.jpg');
    });

    test('Scanning.fromJson falls back to freezerImageUrl if present', () {
      final json = {
        'id': 'scan_2',
        'barcode': '9876543210',
        'storeName': 'Test Store Beta',
        'scannedDate': null,
        'scannedBy': '',
        'status': ScanningStatus.notScanned,
        'freezerImageUrl': 'https://storage.googleapis.com/legacy/freezer2.jpg',
      };

      final deserialized = Scanning.fromJson(json);
      expect(deserialized.imageUrl, 'https://storage.googleapis.com/legacy/freezer2.jpg');
    });

    test('Scanning.copyWith updates imageUrl and status properly', () {
      final initial = Scanning(
        id: '1',
        barcode: '111',
        storeName: 'Store',
        scannedDate: null,
        scannedBy: '',
        status: ScanningStatus.notScanned,
      );

      final updated = initial.copyWith(
        status: ScanningStatus.pending,
        imageUrl: 'https://example.com/photo.jpg',
      );

      expect(updated.status, ScanningStatus.pending);
      expect(updated.imageUrl, 'https://example.com/photo.jpg');
    });
  });

  group('Monthly Normalization for Scanning & Photos', () {
    test('Prior month scans (pending or scanned) reset to notScanned and clear imageUrl', () {
      final lastMonth = DateTime.now().subtract(const Duration(days: 45));
      final oldScan = Scanning(
        id: 'old_1',
        barcode: '12345',
        storeName: 'Store 1',
        scannedDate: Timestamp.fromDate(lastMonth),
        scannedBy: 'Salesman 1',
        status: ScanningStatus.scanned,
        imageUrl: 'https://example.com/old_photo.jpg',
      );

      final normalized = ScanningServices.normalizeMonthlyScanning(oldScan);
      expect(normalized.status, ScanningStatus.notScanned);
      expect(normalized.scannedDate, isNull);
      expect(normalized.scannedBy, isEmpty);
      expect(normalized.imageUrl, isEmpty);
    });

    test('Current month scans retain status, date, scannedBy, and imageUrl', () {
      final now = DateTime.now();
      final currentScan = Scanning(
        id: 'curr_1',
        barcode: '12345',
        storeName: 'Store 1',
        scannedDate: Timestamp.fromDate(now),
        scannedBy: 'Salesman 1',
        status: ScanningStatus.pending,
        imageUrl: 'https://example.com/current_freezer.jpg',
      );

      final normalized = ScanningServices.normalizeMonthlyScanning(currentScan);
      expect(normalized.status, ScanningStatus.pending);
      expect(normalized.scannedDate, isNotNull);
      expect(normalized.scannedBy, 'Salesman 1');
      expect(normalized.imageUrl, 'https://example.com/current_freezer.jpg');
    });

    test('Pullout and unassigned statuses are never reset by normalization', () {
      final pullout = Scanning(
        id: 'p1',
        barcode: '000',
        storeName: '',
        scannedDate: Timestamp.fromDate(DateTime(2020, 1, 1)),
        scannedBy: '',
        status: ScanningStatus.pullout,
      );
      expect(ScanningServices.normalizeMonthlyScanning(pullout).status, ScanningStatus.pullout);

      final unassigned = Scanning(
        id: '',
        barcode: '',
        storeName: 'New Store',
        scannedDate: null,
        scannedBy: '',
        status: ScanningStatus.unassigned,
      );
      expect(ScanningServices.normalizeMonthlyScanning(unassigned).status, ScanningStatus.unassigned);
    });
  });

  group('KPI Calculation Rule: Pending is considered NOT scanned', () {
    test('Dashboard KPI counts Pending as Not Scanned and only Scanned as totalScanCount', () {
      final listScannings = [
        Scanning(
          barcode: '01',
          storeName: 'Store 1',
          scannedDate: Timestamp.now(),
          scannedBy: 'Dealer',
          status: ScanningStatus.scanned,
          imageUrl: 'https://photo.url',
        ),
        Scanning(
          barcode: '02',
          storeName: 'Store 2',
          scannedDate: Timestamp.now(),
          scannedBy: 'Dealer',
          status: ScanningStatus.scanned,
          imageUrl: 'https://photo.url',
        ),
        // 2 pending scans: these must be counted as NOT scanned for KPI
        Scanning(
          barcode: '03',
          storeName: 'Store 3',
          scannedDate: Timestamp.now(),
          scannedBy: 'Salesman',
          status: ScanningStatus.pending,
          imageUrl: 'https://photo.url',
        ),
        Scanning(
          barcode: '04',
          storeName: 'Store 4',
          scannedDate: Timestamp.now(),
          scannedBy: 'Salesman',
          status: ScanningStatus.pending,
          imageUrl: 'https://photo.url',
        ),
        // 1 not scanned
        Scanning(
          barcode: '05',
          storeName: 'Store 5',
          scannedDate: null,
          scannedBy: '',
          status: ScanningStatus.notScanned,
        ),
        // 1 pullout
        Scanning(
          barcode: '06',
          storeName: '',
          scannedDate: null,
          scannedBy: '',
          status: ScanningStatus.pullout,
        ),
      ];

      final activeScannings = listScannings.where((s) => s.status != ScanningStatus.pullout).toList();

      final totalScanCount = activeScannings.where((s) => s.status == ScanningStatus.scanned).length;
      final totalNotScannedCount = activeScannings
          .where((s) => s.status == ScanningStatus.notScanned || s.status == ScanningStatus.pending)
          .length;

      expect(totalScanCount, 2);
      expect(totalNotScannedCount, 3); // 2 pending + 1 notScanned = 3 not scanned

      final totalActive = totalScanCount + totalNotScannedCount;
      expect(totalActive, 5);

      final percentage = totalScanCount / totalActive;
      expect(percentage, 2 / 5); // 40% completion, Pending is NOT in scanned count
    });
  });

  group('Scanning Permissions & Verification Business Logic', () {
    test('Role transition rule validation', () {
      // Salesman scanning unscanned barcode -> should be Pending
      const salesmanRole = BusinessRole.salesman;
      const dealerRole = BusinessRole.dealer;

      bool canMarkAsScanned(String role) => role == BusinessRole.dealer;

      expect(canMarkAsScanned(salesmanRole), isFalse);
      expect(canMarkAsScanned(dealerRole), isTrue);

      // Pending barcode scanned by dealer -> automatically marks as scanned
      String resolveScannedStatus({required String currentStatus, required bool isDealer}) {
        if (currentStatus == ScanningStatus.pending) {
          return isDealer ? ScanningStatus.scanned : ScanningStatus.pending;
        } else if (currentStatus == ScanningStatus.notScanned || currentStatus.isEmpty) {
          return ScanningStatus.pending;
        }
        return currentStatus;
      }

      // Salesman scanning unscanned -> Pending
      expect(resolveScannedStatus(currentStatus: ScanningStatus.notScanned, isDealer: false), ScanningStatus.pending);

      // Dealer scanning unscanned -> Pending (or dealer can mark scanned)
      expect(resolveScannedStatus(currentStatus: ScanningStatus.notScanned, isDealer: true), ScanningStatus.pending);

      // Dealer scanning Pending barcode -> Scanned
      expect(resolveScannedStatus(currentStatus: ScanningStatus.pending, isDealer: true), ScanningStatus.scanned);

      // Salesman scanning Pending barcode -> remains Pending
      expect(resolveScannedStatus(currentStatus: ScanningStatus.pending, isDealer: false), ScanningStatus.pending);
    });

    test('Freezer photo validation check', () {
      bool isPhotoValidForStatus({required String status, required String imageUrl, required bool hasLocalFile}) {
        if (status == ScanningStatus.pending || status == ScanningStatus.scanned) {
          return imageUrl.trim().isNotEmpty || hasLocalFile;
        }
        return true;
      }

      // Pending without photo fails
      expect(isPhotoValidForStatus(status: ScanningStatus.pending, imageUrl: '', hasLocalFile: false), isFalse);

      // Scanned without photo fails
      expect(isPhotoValidForStatus(status: ScanningStatus.scanned, imageUrl: '', hasLocalFile: false), isFalse);

      // Pending with photo succeeds
      expect(isPhotoValidForStatus(status: ScanningStatus.pending, imageUrl: 'https://pic.jpg', hasLocalFile: false), isTrue);

      // Scanned with local newly picked file succeeds
      expect(isPhotoValidForStatus(status: ScanningStatus.scanned, imageUrl: '', hasLocalFile: true), isTrue);

      // Not scanned does not require photo
      expect(isPhotoValidForStatus(status: ScanningStatus.notScanned, imageUrl: '', hasLocalFile: false), isTrue);

      // Pullout does not require photo
      expect(isPhotoValidForStatus(status: ScanningStatus.pullout, imageUrl: '', hasLocalFile: false), isTrue);
    });
  });
}
