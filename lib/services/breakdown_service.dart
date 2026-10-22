import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/views/widgets/marked_date_picker.dart';

// ignore: constant_identifier_names
const String BREAKDOWN_COLLECTION_REF = 'breakdown';

class BreakdownService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _breakdownRef;

  BreakdownService() {
    _breakdownRef = _firestore
        .collection(BREAKDOWN_COLLECTION_REF)
        .withConverter<Breakdown>(
          fromFirestore: (snapshots, _) =>
              Breakdown.fromJson(snapshots.data()!),
          toFirestore: (breakdown, _) => breakdown.toJson(),
        );
  }

  /// Default scan window cutoff (last 1 month)
  static DateTime get defaultCutoffDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, now.day);
  }

  /// Parses date from dynamic raw value (Timestamp or ISO String).
  static DateTime? parseBreakdownDate(dynamic rawDate) {
    if (rawDate is Timestamp) {
      return rawDate.toDate();
    } else if (rawDate is String) {
      return DateTime.tryParse(rawDate);
    }
    return null;
  }

  /// Extracts [UnverifiedSummary] from raw Firestore document snapshots.
  static UnverifiedSummary summaryFromDocs(
    Iterable<QueryDocumentSnapshot> docs, {
    DateTime? cutoffDate,
  }) {
    final cutoff = cutoffDate ?? defaultCutoffDate;
    final dates = <DateTime>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      if ((data['isVerifiedByDealer'] as bool?) == true) continue;

      final date = parseBreakdownDate(data['breakdownDate']);
      if (date == null) continue;

      final dateOnly = DateTime(date.year, date.month, date.day);
      if (dateOnly.isBefore(cutoff)) continue;

      dates.add(dateOnly);
    }

    DateTime? oldest;
    if (dates.isNotEmpty) {
      oldest = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    }

    return UnverifiedSummary(
      count: dates.length,
      oldest: oldest,
      dates: dates,
    );
  }

  Future<Breakdown?> getDocumentsBySpecificDate(DateTime breakdownDate) async {
    DateTime startOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
    );
    DateTime endOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
      23,
      59,
      59,
    );

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .where(
            'breakdownDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'breakdownDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      return querySnapshot.docs.map((doc) {
        return Breakdown.fromJson(doc.data() as Map<String, dynamic>);
      }).first;
    } catch (e) {
      return null;
    }
  }

  Future<String> getIDofBreakdown(DateTime breakdownDate) async {
    DateTime startOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
    );
    DateTime endOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
      23,
      59,
      59,
    );

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .where(
            'breakdownDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'breakdownDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return '';

      return querySnapshot.docs[0].id;
    } catch (e) {
      return '';
    }
  }

  void addBreakdown(Breakdown breakdown) {
    _breakdownRef.add(breakdown);
  }

  void updateBreakdown(String breakdownID, Breakdown breakdown) {
    _breakdownRef.doc(breakdownID).update(breakdown.toJson());
  }

  void deleteBreakdown(String breakdownID) {
    _breakdownRef.doc(breakdownID).delete();
  }

  /// Real-time stream of the [UnverifiedSummary] within the scan window.
  Stream<UnverifiedSummary> getUnverifiedSummaryStream({DateTime? cutoffDate}) {
    return _firestore
        .collection(BREAKDOWN_COLLECTION_REF)
        .snapshots()
        .map((snapshot) => summaryFromDocs(snapshot.docs, cutoffDate: cutoffDate));
  }

  /// One-time fetch of the [UnverifiedSummary] within the scan window.
  static Future<UnverifiedSummary> getUnverifiedSummary({DateTime? cutoffDate}) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .get();
      return summaryFromDocs(snapshot.docs, cutoffDate: cutoffDate);
    } catch (e) {
      return UnverifiedSummary.empty;
    }
  }

  /// Real-time stream of the count of breakdown records not yet verified by the dealer.
  /// If [month] is omitted, counts ALL unverified records within the backlog window (last 1 month).
  Stream<int> getUnverifiedBreakdownsCountStream({DateTime? month, DateTime? cutoffDate}) {
    return getUnverifiedSummaryStream(cutoffDate: cutoffDate).map((summary) {
      if (month != null) {
        return summary.dates.where((d) => d.year == month.year && d.month == month.month).length;
      }
      return summary.count;
    });
  }

  /// One-time count of breakdown records not yet verified by the dealer.
  /// If [month] is omitted, counts ALL unverified records within the backlog window (last 1 month).
  static Future<int> getCountUnverifiedBreakdowns({DateTime? month, DateTime? cutoffDate}) async {
    final summary = await getUnverifiedSummary(cutoffDate: cutoffDate);
    if (month != null) {
      return summary.dates.where((d) => d.year == month.year && d.month == month.month).length;
    }
    return summary.count;
  }

  /// Dates (date-only) of breakdown records not yet verified by the dealer within the scan window.
  static Future<Set<DateTime>> getUnverifiedBreakdownDates({DateTime? cutoffDate}) async {
    final summary = await getUnverifiedSummary(cutoffDate: cutoffDate);
    return summary.dates;
  }

  /// Map of dates to [DayStatus] for calendar visualization (pending vs verified).
  static Future<Map<DateTime, DayStatus>> getBreakdownDayStatuses({DateTime? cutoffDate}) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .get();
      final cutoff = cutoffDate ?? defaultCutoffDate;
      final map = <DateTime, DayStatus>{};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final date = parseBreakdownDate(data['breakdownDate']);
        if (date == null) continue;

        final dateOnly = DateTime(date.year, date.month, date.day);
        if (dateOnly.isBefore(cutoff)) continue;

        final isVerified = (data['isVerifiedByDealer'] as bool?) == true;
        if (!isVerified) {
          // Any unverified record makes the day pending
          map[dateOnly] = DayStatus.pending;
        } else if (!map.containsKey(dateOnly)) {
          map[dateOnly] = DayStatus.done;
        }
      }
      return map;
    } catch (e) {
      return {};
    }
  }
}
