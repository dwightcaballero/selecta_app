import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/services/configuration_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';

/// Data class representing the loaded configuration state.
class ConfigurationLoadResult {
  final Configuration config;
  final bool existsInDb;
  final DateTime startDate;
  final DateTime endDate;

  ConfigurationLoadResult({
    required this.config,
    required this.existsInDb,
    required this.startDate,
    required this.endDate,
  });
}

/// Controller managing application and campaign settings business logic,
/// persistence, validation, cache invalidation, and audit logging.
class ConfigurationController {
  final ConfigurationService _configService;

  ConfigurationController({ConfigurationService? configService})
      : _configService = configService ?? ConfigurationService();

  /// Loads configuration settings from the backend service.
  Future<ConfigurationLoadResult> loadConfiguration() async {
    final exists = await _configService.configurationExists();
    final config = await _configService.getConfiguration();

    final start = config.merchBlitzStartDate.toDate();
    final end = config.merchBlitzEndDate.toDate();

    return ConfigurationLoadResult(
      config: config,
      existsInDb: exists,
      startDate: DateTime(start.year, start.month, start.day),
      endDate: DateTime(end.year, end.month, end.day),
    );
  }

  /// Validates dates, saves configuration to Firestore, invalidates relevant caches,
  /// and writes an audit log trail.
  Future<void> saveConfiguration({
    required DateTime startDate,
    required DateTime endDate,
    required Configuration? originalConfig,
    required bool existsInDb,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('Merch Blitz End Date must be after or equal to the Start Date.');
    }

    final newStartDateTs = Timestamp.fromDate(startDate);
    final newEndDateTs = Timestamp.fromDate(endDate);
    final config = Configuration(
      merchBlitzStartDate: newStartDateTs,
      merchBlitzEndDate: newEndDateTs,
    );

    await _configService.saveConfiguration(config);
    HapiStoreService.invalidateCache();

    // Record transaction log for the audit trail
    final newMap = {
      'Merch Blitz Start Date': newStartDateTs,
      'Merch Blitz End Date': newEndDateTs,
    };

    if (existsInDb && originalConfig != null) {
      final oldMap = {
        'Merch Blitz Start Date': originalConfig.merchBlitzStartDate,
        'Merch Blitz End Date': originalConfig.merchBlitzEndDate,
      };
      await Helperfunctions.logUpdate(
        'Configuration - Merch Blitz Schedule',
        oldMap,
        newMap,
        page: AppPages.configuration,
      );
    } else {
      await Helperfunctions.logCreate(
        'Configuration - Merch Blitz Schedule',
        newMap,
        page: AppPages.configuration,
      );
    }
  }
}
