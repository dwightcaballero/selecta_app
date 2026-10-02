import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    bool aiEnabled = true,
    String geminiApiKey = '',
    int aiMonthlyRequestLimit = 3000,
    double? salesTarget,
    double? buyingTargetPercentage,
    double? throughputTarget,
    double? placementTargetPercentage,
    double? scanningTargetPercentage,
    int? expansionTarget,
    String? superAdminPasswordHash,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('Merch Blitz End Date must be after or equal to the Start Date.');
    }

    final newStartDateTs = Timestamp.fromDate(startDate);
    final newEndDateTs = Timestamp.fromDate(endDate);
    final finalSalesTarget = salesTarget ?? originalConfig?.salesTarget ?? 1000000.0;
    final finalBuyingPct = buyingTargetPercentage ?? originalConfig?.buyingTargetPercentage ?? 80.0;
    final finalThroughputTarget = throughputTarget ?? originalConfig?.throughputTarget ?? 8000.0;
    final finalPlacementPct = placementTargetPercentage ?? originalConfig?.placementTargetPercentage ?? 80.0;
    final finalScanningPct = scanningTargetPercentage ?? originalConfig?.scanningTargetPercentage ?? 100.0;
    final finalExpansionTarget = expansionTarget ?? originalConfig?.expansionTarget ?? 10;
    final finalSuperAdminHash = superAdminPasswordHash ?? originalConfig?.superAdminPasswordHash ?? '';

    final config = Configuration(
      merchBlitzStartDate: newStartDateTs,
      merchBlitzEndDate: newEndDateTs,
      aiEnabled: aiEnabled,
      geminiApiKey: geminiApiKey.trim(),
      aiMonthlyRequestLimit: aiMonthlyRequestLimit,
      superAdminPasswordHash: finalSuperAdminHash,
      salesTarget: finalSalesTarget,
      buyingTargetPercentage: finalBuyingPct,
      throughputTarget: finalThroughputTarget,
      placementTargetPercentage: finalPlacementPct,
      scanningTargetPercentage: finalScanningPct,
      expansionTarget: finalExpansionTarget,
    );

    await _configService.saveConfiguration(config);
    HapiStoreService.invalidateCache();

    // Record transaction log for the audit trail
    final newMap = {
      'Merch Blitz Start Date': newStartDateTs,
      'Merch Blitz End Date': newEndDateTs,
      'AI Enabled': aiEnabled,
      'AI Monthly Request Limit': aiMonthlyRequestLimit,
      'Sales Target': finalSalesTarget,
      'Buying Target Percentage': finalBuyingPct,
      'Throughput Target': finalThroughputTarget,
      'Placement Target Percentage': finalPlacementPct,
      'Scanning Target Percentage': finalScanningPct,
      'Expansion Target': finalExpansionTarget,
    };

    if (existsInDb && originalConfig != null) {
      final oldMap = {
        'Merch Blitz Start Date': originalConfig.merchBlitzStartDate,
        'Merch Blitz End Date': originalConfig.merchBlitzEndDate,
        'AI Enabled': originalConfig.aiEnabled,
        'AI Monthly Request Limit': originalConfig.aiMonthlyRequestLimit,
        'Sales Target': originalConfig.salesTarget,
        'Buying Target Percentage': originalConfig.buyingTargetPercentage,
        'Throughput Target': originalConfig.throughputTarget,
        'Placement Target Percentage': originalConfig.placementTargetPercentage,
        'Scanning Target Percentage': originalConfig.scanningTargetPercentage,
        'Expansion Target': originalConfig.expansionTarget,
      };
      await Helperfunctions.logUpdate(
        'Configuration - App & KPI Settings',
        oldMap,
        newMap,
        page: AppPages.configuration,
      );
    } else {
      await Helperfunctions.logCreate(
        'Configuration - App & KPI Settings',
        newMap,
        page: AppPages.configuration,
      );
    }
  }

  /// Retrieves the saved Gemini API key from local preferences or remote Firestore config.
  Future<String?> getGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final localKey = prefs.getString('gemini_api_key');
    if (localKey != null && localKey.isNotEmpty) return localKey;
    final config = await _configService.getConfiguration();
    if (config.geminiApiKey.isNotEmpty) return config.geminiApiKey;
    return GeminiAiService.defaultApiKey;
  }

  /// Saves the Gemini API key in local storage.
  Future<void> saveGeminiApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (apiKey.trim().isEmpty) {
      await prefs.remove('gemini_api_key');
    } else {
      await prefs.setString('gemini_api_key', apiKey.trim());
    }
  }

  /// Gets current month usage count from GeminiAiService.
  Future<int> getCurrentAiUsage() async {
    return GeminiAiService().getCurrentMonthUsage();
  }
}


