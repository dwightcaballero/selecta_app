import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/sub_category.dart';

class Configuration {
  Timestamp merchBlitzStartDate;
  Timestamp merchBlitzEndDate;
  bool aiEnabled;
  String geminiApiKey;
  int aiMonthlyRequestLimit;
  /// SHA-256 hash of the super-admin password. Never store the plain-text password here.
  String superAdminPasswordHash;

  // KPI Monthly Targets
  double salesTarget;
  double buyingTargetPercentage;
  double throughputTarget;
  double placementTargetPercentage;
  double scanningTargetPercentage;
  int expansionTarget;

  // Placement product pairs (when either is delivered, both are placed)
  List<PlacementPair> placementPairs;

  // Credit Reminder SMS Template
  static const String defaultCreditReminderSmsTemplate =
      '[SELECTA CREDIT REMINDER]\n'
      'Good day {storeName}!\n'
      'This is a friendly reminder regarding your outstanding Selecta credit balance of {creditAmount} from {creditDate} ({daysOverdue} days overdue).\n'
      'Kindly prepare the payment for our sales representative. Thank you for your continued partnership!';

  /// Whether barcode scanning is enabled for picklists
  bool enablePicklistBarcodeScanner;

  String creditReminderSmsTemplate;

  // Inventory Audit & Hardening Configuration
  int unitApprovalThreshold;
  bool blindCountEnabled;
  int recountThreshold;
  int maxAdjustmentsPerUser24h;
  int maxAdjustmentsPerProduct7d;
  double maxWriteOffPercentage;
  int repeatedShortPickThreshold;
  Timestamp? lastStockAuditAt;

  // Product Sorting Configuration
  String productSortMode; // 'srp' | 'custom'
  List<SubCategory> subCategories;

  // Hapi Store Self-Ordering Settings (Optional)
  double? storeMinimumOrderValue;
  String? storeCutoffTime; // "HH:mm" 24h format e.g. "17:00"

  Configuration({
    required this.merchBlitzStartDate,
    required this.merchBlitzEndDate,
    this.aiEnabled = true,
    this.geminiApiKey = '',
    this.aiMonthlyRequestLimit = 3000,
    this.superAdminPasswordHash = '',
    this.salesTarget = 1000000.0,
    this.buyingTargetPercentage = 80.0,
    this.throughputTarget = 8000.0,
    this.placementTargetPercentage = 80.0,
    this.scanningTargetPercentage = 100.0,
    this.expansionTarget = 10,
    this.placementPairs = const [],
    this.enablePicklistBarcodeScanner = true,
    this.creditReminderSmsTemplate = defaultCreditReminderSmsTemplate,
    this.unitApprovalThreshold = 10,
    this.blindCountEnabled = true,
    this.recountThreshold = 5,
    this.maxAdjustmentsPerUser24h = 5,
    this.maxAdjustmentsPerProduct7d = 3,
    this.maxWriteOffPercentage = 10.0,
    this.repeatedShortPickThreshold = 3,
    this.lastStockAuditAt,
    this.productSortMode = 'srp',
    this.subCategories = const [],
    this.storeMinimumOrderValue,
    this.storeCutoffTime,
  });

  bool get hasStoreMinimumOrderValue => storeMinimumOrderValue != null && storeMinimumOrderValue! > 0;
  bool get hasStoreCutoffTime => storeCutoffTime != null && storeCutoffTime!.trim().isNotEmpty;

  /// Returns true if [time] is after the configured daily cut-off time.
  bool isAfterCutoff(DateTime time) {
    if (!hasStoreCutoffTime) return false;
    try {
      final parts = storeCutoffTime!.trim().split(':');
      if (parts.length >= 2) {
        final cutoffHour = int.parse(parts[0]);
        final cutoffMinute = int.parse(parts[1]);
        final cutoffToday = DateTime(time.year, time.month, time.day, cutoffHour, cutoffMinute);
        return time.isAfter(cutoffToday);
      }
    } catch (_) {}
    return false;
  }

  /// Returns true if [plainTextPassword] matches the stored SHA-256 hash.
  bool verifyAdminPassword(String plainTextPassword) {
    if (superAdminPasswordHash.isEmpty) return false;
    final hash = sha256.convert(utf8.encode(plainTextPassword.trim())).toString();
    return hash == superAdminPasswordHash;
  }

  /// Converts a plain-text password into a SHA-256 hash string for storage.
  static String hashPassword(String plainTextPassword) {
    return sha256.convert(utf8.encode(plainTextPassword.trim())).toString();
  }

  // Alternate casing accessor for flexibility
  // ignore: non_constant_identifier_names
  Timestamp get MerchiBlitzEndDate => merchBlitzEndDate;
  // ignore: non_constant_identifier_names
  set MerchiBlitzEndDate(Timestamp value) => merchBlitzEndDate = value;

  static Configuration empty() => Configuration(
        merchBlitzStartDate: Timestamp.now(),
        merchBlitzEndDate: Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        aiEnabled: true,
        geminiApiKey: '',
        aiMonthlyRequestLimit: 3000,
        superAdminPasswordHash: '',
        salesTarget: 1000000.0,
        buyingTargetPercentage: 80.0,
        throughputTarget: 8000.0,
        placementTargetPercentage: 80.0,
        scanningTargetPercentage: 100.0,
        expansionTarget: 10,
        placementPairs: const [],
        enablePicklistBarcodeScanner: true,
        creditReminderSmsTemplate: defaultCreditReminderSmsTemplate,
        unitApprovalThreshold: 10,
        blindCountEnabled: true,
        recountThreshold: 5,
        maxAdjustmentsPerUser24h: 5,
        maxAdjustmentsPerProduct7d: 3,
        maxWriteOffPercentage: 10.0,
        repeatedShortPickThreshold: 3,
        lastStockAuditAt: null,
        productSortMode: 'srp',
        subCategories: const [],
      );

  Configuration.fromJson(Map<String, Object?> json)
      : this(
          merchBlitzStartDate: (json['merchBlitzStartDate'] is Timestamp)
              ? json['merchBlitzStartDate'] as Timestamp
              : (json['MerchiBlitzStartDate'] is Timestamp)
                  ? json['MerchiBlitzStartDate'] as Timestamp
                  : Timestamp.now(),
          merchBlitzEndDate: (json['merchBlitzEndDate'] is Timestamp)
              ? json['merchBlitzEndDate'] as Timestamp
              : (json['MerchiBlitzEndDate'] is Timestamp)
                  ? json['MerchiBlitzEndDate'] as Timestamp
                  : Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
          aiEnabled: json['aiEnabled'] as bool? ?? true,
          geminiApiKey: json['geminiApiKey'] as String? ?? '',
          aiMonthlyRequestLimit: (json['aiMonthlyRequestLimit'] as num?)?.toInt() ?? 3000,
          superAdminPasswordHash: json['superAdminPasswordHash'] as String? ?? '',
          salesTarget: (json['salesTarget'] as num?)?.toDouble() ?? 1000000.0,
          buyingTargetPercentage: (json['buyingTargetPercentage'] as num?)?.toDouble() ?? 80.0,
          throughputTarget: (json['throughputTarget'] as num?)?.toDouble() ?? 8000.0,
          placementTargetPercentage: (json['placementTargetPercentage'] as num?)?.toDouble() ?? 80.0,
          scanningTargetPercentage: (json['scanningTargetPercentage'] as num?)?.toDouble() ?? 100.0,
          expansionTarget: (json['expansionTarget'] as num?)?.toInt() ?? 10,
          placementPairs: (json['placementPairs'] is List)
              ? (json['placementPairs'] as List)
                  .whereType<Map>()
                  .map((m) => PlacementPair.fromJson(Map<String, Object?>.from(m)))
                  .toList()
              : const [],
          enablePicklistBarcodeScanner: json['enablePicklistBarcodeScanner'] as bool? ?? true,
          creditReminderSmsTemplate: json['creditReminderSmsTemplate'] as String? ?? defaultCreditReminderSmsTemplate,
          unitApprovalThreshold: (json['unitApprovalThreshold'] as num?)?.toInt() ?? 10,
          blindCountEnabled: json['blindCountEnabled'] as bool? ?? true,
          recountThreshold: (json['recountThreshold'] as num?)?.toInt() ?? 5,
          maxAdjustmentsPerUser24h: (json['maxAdjustmentsPerUser24h'] as num?)?.toInt() ?? 5,
          maxAdjustmentsPerProduct7d: (json['maxAdjustmentsPerProduct7d'] as num?)?.toInt() ?? 3,
          maxWriteOffPercentage: (json['maxWriteOffPercentage'] as num?)?.toDouble() ?? 10.0,
          repeatedShortPickThreshold: (json['repeatedShortPickThreshold'] as num?)?.toInt() ?? 3,
          lastStockAuditAt: json['lastStockAuditAt'] as Timestamp?,
          productSortMode: json['productSortMode'] as String? ?? 'srp',
          subCategories: (json['subCategories'] is List)
              ? (json['subCategories'] as List)
                  .whereType<Map>()
                  .map((m) => SubCategory.fromJson(Map<String, dynamic>.from(m)))
                  .toList()
              : const [],
          storeMinimumOrderValue: (json['storeMinimumOrderValue'] as num?)?.toDouble(),
          storeCutoffTime: json['storeCutoffTime'] as String?,
        );

  Configuration copyWith({
    Timestamp? merchBlitzStartDate,
    Timestamp? merchBlitzEndDate,
    bool? aiEnabled,
    String? geminiApiKey,
    int? aiMonthlyRequestLimit,
    String? superAdminPasswordHash,
    double? salesTarget,
    double? buyingTargetPercentage,
    double? throughputTarget,
    double? placementTargetPercentage,
    double? scanningTargetPercentage,
    int? expansionTarget,
    List<PlacementPair>? placementPairs,
    bool? enablePicklistBarcodeScanner,
    String? creditReminderSmsTemplate,
    int? unitApprovalThreshold,
    bool? blindCountEnabled,
    int? recountThreshold,
    int? maxAdjustmentsPerUser24h,
    int? maxAdjustmentsPerProduct7d,
    double? maxWriteOffPercentage,
    int? repeatedShortPickThreshold,
    Timestamp? lastStockAuditAt,
    String? productSortMode,
    List<SubCategory>? subCategories,
    double? storeMinimumOrderValue,
    bool clearStoreMinimumOrderValue = false,
    String? storeCutoffTime,
    bool clearStoreCutoffTime = false,
  }) {
    return Configuration(
      merchBlitzStartDate: merchBlitzStartDate ?? this.merchBlitzStartDate,
      merchBlitzEndDate: merchBlitzEndDate ?? this.merchBlitzEndDate,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      aiMonthlyRequestLimit: aiMonthlyRequestLimit ?? this.aiMonthlyRequestLimit,
      superAdminPasswordHash: superAdminPasswordHash ?? this.superAdminPasswordHash,
      salesTarget: salesTarget ?? this.salesTarget,
      buyingTargetPercentage: buyingTargetPercentage ?? this.buyingTargetPercentage,
      throughputTarget: throughputTarget ?? this.throughputTarget,
      placementTargetPercentage: placementTargetPercentage ?? this.placementTargetPercentage,
      scanningTargetPercentage: scanningTargetPercentage ?? this.scanningTargetPercentage,
      expansionTarget: expansionTarget ?? this.expansionTarget,
      placementPairs: placementPairs ?? List.from(this.placementPairs),
      enablePicklistBarcodeScanner: enablePicklistBarcodeScanner ?? this.enablePicklistBarcodeScanner,
      creditReminderSmsTemplate: creditReminderSmsTemplate ?? this.creditReminderSmsTemplate,
      unitApprovalThreshold: unitApprovalThreshold ?? this.unitApprovalThreshold,
      blindCountEnabled: blindCountEnabled ?? this.blindCountEnabled,
      recountThreshold: recountThreshold ?? this.recountThreshold,
      maxAdjustmentsPerUser24h: maxAdjustmentsPerUser24h ?? this.maxAdjustmentsPerUser24h,
      maxAdjustmentsPerProduct7d: maxAdjustmentsPerProduct7d ?? this.maxAdjustmentsPerProduct7d,
      maxWriteOffPercentage: maxWriteOffPercentage ?? this.maxWriteOffPercentage,
      repeatedShortPickThreshold: repeatedShortPickThreshold ?? this.repeatedShortPickThreshold,
      lastStockAuditAt: lastStockAuditAt ?? this.lastStockAuditAt,
      productSortMode: productSortMode ?? this.productSortMode,
      subCategories: subCategories ?? List.from(this.subCategories),
      storeMinimumOrderValue: clearStoreMinimumOrderValue ? null : (storeMinimumOrderValue ?? this.storeMinimumOrderValue),
      storeCutoffTime: clearStoreCutoffTime ? null : (storeCutoffTime ?? this.storeCutoffTime),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'merchBlitzStartDate': merchBlitzStartDate,
      'merchBlitzEndDate': merchBlitzEndDate,
      'MerchiBlitzEndDate': merchBlitzEndDate,
      'aiEnabled': aiEnabled,
      'geminiApiKey': geminiApiKey,
      'aiMonthlyRequestLimit': aiMonthlyRequestLimit,
      'superAdminPasswordHash': superAdminPasswordHash,
      'salesTarget': salesTarget,
      'buyingTargetPercentage': buyingTargetPercentage,
      'throughputTarget': throughputTarget,
      'placementTargetPercentage': placementTargetPercentage,
      'scanningTargetPercentage': scanningTargetPercentage,
      'expansionTarget': expansionTarget,
      'placementPairs': placementPairs.map((p) => p.toJson()).toList(),
      'enablePicklistBarcodeScanner': enablePicklistBarcodeScanner,
      'creditReminderSmsTemplate': creditReminderSmsTemplate,
      'unitApprovalThreshold': unitApprovalThreshold,
      'blindCountEnabled': blindCountEnabled,
      'recountThreshold': recountThreshold,
      'maxAdjustmentsPerUser24h': maxAdjustmentsPerUser24h,
      'maxAdjustmentsPerProduct7d': maxAdjustmentsPerProduct7d,
      'maxWriteOffPercentage': maxWriteOffPercentage,
      'repeatedShortPickThreshold': repeatedShortPickThreshold,
      if (lastStockAuditAt != null) 'lastStockAuditAt': lastStockAuditAt,
      'productSortMode': productSortMode,
      'subCategories': subCategories.map((s) => s.toJson()).toList(),
      if (storeMinimumOrderValue != null) 'storeMinimumOrderValue': storeMinimumOrderValue,
      if (storeCutoffTime != null) 'storeCutoffTime': storeCutoffTime,
    };
  }
}
