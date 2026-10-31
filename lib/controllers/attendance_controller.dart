import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/attendance.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/attendance_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';

class LocationCheckResult {
  final Position? position;
  final double? distanceMeters;
  final bool isWithinGeofence;
  final String locationSummary;
  final String? errorMessage;

  LocationCheckResult({
    this.position,
    this.distanceMeters,
    this.isWithinGeofence = false,
    required this.locationSummary,
    this.errorMessage,
  });
}

class AttendanceController {
  final AttendanceService _service = AttendanceService();
  final ConfigurationService _configService = ConfigurationService();

  /// Gets current user profile
  Future<Users?> getCurrentUser() async => await KVariables.getUser();

  /// Gets configuration
  Future<Configuration> getConfiguration() async =>
      await _configService.getConfiguration();

  /// Streams active attendance for today for a salesman
  Stream<Attendance?> streamTodayAttendance(String username) =>
      _service.streamAttendanceForDate(salesmanUsername: username);

  /// Fetches today's attendance for a salesman
  Future<Attendance?> getTodayAttendance(String username) =>
      _service.getAttendanceForDate(salesmanUsername: username);

  /// Acquires current GPS position and evaluates depot proximity
  Future<LocationCheckResult> checkCurrentLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationCheckResult(
          locationSummary: 'Location service disabled',
          errorMessage: 'Device location service is turned off. Please turn on GPS.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationCheckResult(
            locationSummary: 'Permission denied',
            errorMessage: 'Location permissions are denied.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationCheckResult(
          locationSummary: 'Permission denied permanently',
          errorMessage: 'Location permissions are permanently denied. Please enable them in app settings.',
        );
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (e) {
        debugPrint('High accuracy location timed out, falling back to last known: $e');
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        return LocationCheckResult(
          locationSummary: 'Location unavailable',
          errorMessage: 'Could not acquire GPS position.',
        );
      }

      final config = await getConfiguration();
      if (config.hasDepotGeofence) {
        final distance = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          config.depotLatitude!,
          config.depotLongitude!,
        );
        final isInside = distance <= config.depotRadiusMeters;
        final summary = isInside
            ? 'At Depot (${distance.round()}m)'
            : 'Off-site (${distance.round()}m from Depot)';

        return LocationCheckResult(
          position: pos,
          distanceMeters: distance,
          isWithinGeofence: isInside,
          locationSummary: summary,
        );
      } else {
        return LocationCheckResult(
          position: pos,
          distanceMeters: null,
          isWithinGeofence: true, // No depot geofence set yet, treat as on-site
          locationSummary: 'GPS Recorded (No Depot Set)',
        );
      }
    } catch (e) {
      debugPrint('Error in checkCurrentLocation: $e');
      return LocationCheckResult(
        locationSummary: 'Error checking location',
        errorMessage: e.toString(),
      );
    }
  }

  /// Executes Salesman Clock-In
  Future<Attendance> clockIn({
    required Users salesman,
    Position? position,
    double? distanceMeters,
    bool isWithinGeofence = false,
  }) async {
    final now = DateTime.now();
    final result = await _service.clockIn(
      salesmanUsername: salesman.username,
      salesmanFullName: salesman.username,
      dealerName: salesman.dealerName,
      time: now,
      latitude: position?.latitude,
      longitude: position?.longitude,
      distanceToDepot: distanceMeters,
      withinGeofence: isWithinGeofence,
    );

    // Send push notification to dealer topic
    try {
      final locText = isWithinGeofence ? 'At Depot' : 'Off-site';
      await PushNotificationService().sendNotificationToRole(
        role: 'Dealer',
        title: 'Salesman Clock-In',
        body: '${salesman.username} clocked in ($locText). Tap to review.',
      );
    } catch (e) {
      debugPrint('Error sending clock-in notification: $e');
    }

    return result;
  }

  /// Executes Salesman Clock-Out
  Future<Attendance> clockOut({
    required Users salesman,
    Position? position,
    double? distanceMeters,
    bool isWithinGeofence = false,
  }) async {
    final now = DateTime.now();
    final result = await _service.clockOut(
      salesmanUsername: salesman.username,
      time: now,
      latitude: position?.latitude,
      longitude: position?.longitude,
      distanceToDepot: distanceMeters,
      withinGeofence: isWithinGeofence,
    );

    // Send push notification to dealer topic
    try {
      await PushNotificationService().sendNotificationToRole(
        role: 'Dealer',
        title: 'Salesman Clock-Out',
        body: '${salesman.username} clocked out (${result.totalHours} hrs). Tap to review.',
      );
    } catch (e) {
      debugPrint('Error sending clock-out notification: $e');
    }

    return result;
  }

  /// Streams list of all attendances for dealer today
  Stream<List<Attendance>> streamDealerAttendances(String dealerName, DateTime date) =>
      _service.streamAttendancesForDate(dealerName: dealerName, date: date);

  /// Streams pending approvals count for dealer
  Stream<int> streamPendingCount(String dealerName, DateTime date) =>
      _service.streamPendingApprovalsCount(dealerName: dealerName, date: date);

  /// Approves clock-in
  Future<void> approveClockIn(String id, String dealerUsername) =>
      _service.approveClockIn(attendanceId: id, dealerUsername: dealerUsername);

  /// Approves clock-out
  Future<void> approveClockOut(String id, String dealerUsername) =>
      _service.approveClockOut(attendanceId: id, dealerUsername: dealerUsername);

  /// Batch approve all
  Future<int> batchApproveAll(String dealerName, DateTime date, String dealerUsername) =>
      _service.batchApproveAll(dealerName: dealerName, date: date, dealerUsername: dealerUsername);

  /// Gets weekly attendance timesheet
  Future<List<Attendance>> getWeeklyTimesheet({
    required String salesmanUsername,
    required DateTime startDate,
    required DateTime endDate,
  }) =>
      _service.getWeeklyAttendances(
        salesmanUsername: salesmanUsername,
        startDate: startDate,
        endDate: endDate,
      );

  /// Gets unclocked salesmen for date
  Future<List<Attendance>> getUnclockedSalesmenForDate({
    required String dealerName,
    required DateTime date,
  }) =>
      _service.getUnclockedSalesmenForDate(dealerName: dealerName, date: date);

  /// Overrides a salesman day credit
  Future<void> overrideDayCredit({
    required String attendanceId,
    required double credit,
    String? remarks,
    required String dealerUsername,
  }) =>
      _service.overrideDayCredit(
        attendanceId: attendanceId,
        newCredit: credit,
        remarks: remarks,
        dealerUsername: dealerUsername,
      );
}
