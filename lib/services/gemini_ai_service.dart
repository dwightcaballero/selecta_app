import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/image_slicing_service.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

/// A confirmed item that was present on the official supplier invoice during Phase 2.
class ConfirmedInvoiceItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String productSource;
  final String category;
  final String tag;
  final double unitCost;
  final double sellingPrice;
  final int orderedQuantity;
  final int deliveredQuantity;

  const ConfirmedInvoiceItem({
    required this.productId,
    required this.productName,
    this.imageUrl = '',
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    required this.unitCost,
    this.sellingPrice = 0.0,
    required this.orderedQuantity,
    required this.deliveredQuantity,
  });

  double get lineTotal => deliveredQuantity * unitCost;
}

/// Result of comparing an official paper invoice against the original PO items.
class InvoiceComparisonResult {
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final double totalAmount;
  final List<ConfirmedInvoiceItem> confirmedItems;
  final List<OrderItem> missingItems;
  final String rawAiResponse;

  const InvoiceComparisonResult({
    this.invoiceNumber = '',
    this.invoiceDate,
    this.totalAmount = 0.0,
    this.confirmedItems = const [],
    this.missingItems = const [],
    this.rawAiResponse = '',
  });

  double get confirmedTotal => confirmedItems.fold(0.0, (acc, i) => acc + i.lineTotal);
  int get totalDeliveredUnits => confirmedItems.fold(0, (acc, i) => acc + i.deliveredQuantity);
}

/// Represents an item on the invoice that was truncated, had low confidence, or had multiple plausible matches.
class AmbiguousPoItem {
  final String rawText;
  final int quantity;
  final double detectedUnitPrice;
  final List<String> candidateProductIds;
  final String reason;
  final int? documentIndex;

  const AmbiguousPoItem({
    required this.rawText,
    required this.quantity,
    this.detectedUnitPrice = 0.0,
    this.candidateProductIds = const [],
    this.reason = '',
    this.documentIndex,
  });
}

/// Result containing extracted purchase order data from Gemini multimodal vision.
class ExtractedPurchaseOrderData {
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final double totalAmount;
  final List<ExtractedPoItem> matchedItems;
  final List<AmbiguousPoItem> ambiguousItems;
  final List<String> unmatchedItems;
  final String rawAiResponse;

  const ExtractedPurchaseOrderData({
    this.invoiceNumber = '',
    this.invoiceDate,
    this.totalAmount = 0.0,
    this.matchedItems = const [],
    this.ambiguousItems = const [],
    this.unmatchedItems = const [],
    this.rawAiResponse = '',
  });

  int get totalExtractedUnits =>
      matchedItems.fold(0, (acc, i) => acc + i.quantity) +
      ambiguousItems.fold(0, (acc, i) => acc + i.quantity);
}

class ExtractedPoItem {
  final String productId;
  final String matchedProductName;
  final String rawText;
  final int quantity;
  final double confidence;

  const ExtractedPoItem({
    required this.productId,
    required this.matchedProductName,
    required this.rawText,
    required this.quantity,
    this.confidence = 1.0,
  });
}

/// Result of extracting supplier daily available stock status from document images.
class ExtractedSupplierStockData {
  final DateTime? reportDate;
  final List<SupplierStockItemStatus> matchedItems;
  final List<String> outOfStockProductIds;
  final List<String> inStockProductIds;
  final String rawAiResponse;

  const ExtractedSupplierStockData({
    this.reportDate,
    this.matchedItems = const [],
    this.outOfStockProductIds = const [],
    this.inStockProductIds = const [],
    this.rawAiResponse = '',
  });

  bool isProductOutOfStock(String productId) => outOfStockProductIds.contains(productId);
}

class SupplierStockItemStatus {
  final String productId;
  final String matchedProductName;
  final String rawText;
  final bool isOutOfStock;
  final int? supplierAvailableQuantity;

  const SupplierStockItemStatus({
    required this.productId,
    required this.matchedProductName,
    required this.rawText,
    required this.isOutOfStock,
    this.supplierAvailableQuantity,
  });
}

/// Result status when verifying if AI operations are allowed.
class AiStatusCheck {
  final bool isAllowed;
  final String? message;
  final int currentUsage;
  final int limit;

  AiStatusCheck({
    required this.isAllowed,
    this.message,
    this.currentUsage = 0,
    this.limit = 1000,
  });
}

/// Service managing communication with the Google Gemini API for Selecta operations,
/// including remote key fetching, master enable/disable, and quota tracking/enforcement.
class GeminiAiService {
  static const List<String> _candidateModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-flash-latest',
  ];
  static const String _usageCollection = 'ai_usage_metrics';
  static const String defaultApiKey = '';

  final ConfigurationService _configService = ConfigurationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _activeModelIndex = 0;
  GenerativeModel? _model;
  ChatSession? _chatSession;
  String? _cachedApiKey;
  String? _cachedContextPrompt;

  static final GeminiAiService _instance = GeminiAiService._internal();
  factory GeminiAiService() => _instance;
  GeminiAiService._internal();

  /// Gets the current month key for quota tracking (e.g. "2026-09").
  String get _currentMonthKey => DateFormat('yyyy-MM').format(DateTime.now());

  /// Checks if AI is enabled and whether quota has not been exceeded.
  Future<AiStatusCheck> checkAiAvailability() async {
    final config = await _configService.getConfiguration();

    // 1. Check if disabled globally
    if (!config.aiEnabled) {
      return AiStatusCheck(
        isAllowed: false,
        message: 'The AI Assistant is currently disabled by your Administrator.',
      );
    }

    // 2. Check if API key is configured
    final apiKey = await getEffectiveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return AiStatusCheck(
        isAllowed: false,
        message: 'AI Assistant is not configured yet. Please configure the Gemini Key in Configurations.',
      );
    }

    // 3. Check monthly quota usage in Firestore
    final currentUsage = await getCurrentMonthUsage();
    final limit = config.aiMonthlyRequestLimit;

    if (limit > 0 && currentUsage >= limit) {
      return AiStatusCheck(
        isAllowed: false,
        currentUsage: currentUsage,
        limit: limit,
        message: 'Monthly AI quota limit reached ($currentUsage / $limit calls). '
            'The AI Assistant is paused to prevent unexpected costs.',
      );
    }

    // Warning zone: 90% quota reached
    if (limit > 0 && currentUsage >= (limit * 0.90).floor()) {
      return AiStatusCheck(
        isAllowed: true,
        currentUsage: currentUsage,
        limit: limit,
        message: '⚠️ Quota Alert: $currentUsage of $limit monthly requests used (~${((currentUsage / limit) * 100).toStringAsFixed(0)}%).',
      );
    }

    return AiStatusCheck(
      isAllowed: true,
      currentUsage: currentUsage,
      limit: limit,
    );
  }

  /// Returns the current monthly usage count.
  Future<int> getCurrentMonthUsage() async {
    try {
      final doc = await _firestore.collection(_usageCollection).doc(_currentMonthKey).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['requestCount'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Increments the monthly AI usage counter in Firestore.
  Future<void> recordAiUsage() async {
    try {
      final docRef = _firestore.collection(_usageCollection).doc(_currentMonthKey);
      await docRef.set({
        'requestCount': FieldValue.increment(1),
        'lastUsed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Retrieves the active API key. First checks remote shared configuration (Firestore),
  /// falling back to compile-time env (--dart-define=GEMINI_API_KEY).
  Future<String?> getEffectiveApiKey() async {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey;
    }

    // 1. Fetch from Firestore shared configuration (so 1 key works for all users)
    try {
      final config = await _configService.getConfiguration();
      if (config.geminiApiKey.isNotEmpty) {
        _cachedApiKey = config.geminiApiKey.trim();
        return _cachedApiKey;
      }
    } catch (_) {}

    // 2. Fallback: check compile-time environment variable
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty) {
      _cachedApiKey = envKey;
      return envKey;
    }

    // 3. Fallback: pre-configured developer key
    if (defaultApiKey.isNotEmpty) {
      _cachedApiKey = defaultApiKey;
      return defaultApiKey;
    }

    return null;
  }

  void invalidateCachedKey() {
    _cachedApiKey = null;
    _model = null;
    _chatSession = null;
  }

  /// Initializes or re-initializes the generative model with system instructions.
  Future<GenerativeModel?> getModel({String? contextPrompt, int? modelIndex}) async {
    final key = await getEffectiveApiKey();
    if (key == null || key.isEmpty) return null;

    final targetIndex = modelIndex ?? _activeModelIndex;
    final modelName = _candidateModels[targetIndex % _candidateModels.length];

    final systemInstruction = Content.system(
      'You are Sedy, an intelligent operations AI assistant embedded directly inside the Selecta Distribution & Sales mobile app. '
      'Your role is to assist Selecta dealers and salesmen with daily sales, delivery tracking, store visits (PJP - Permanent Journey Plan), '
      'bad order inspections, Merch Blitz campaigns, throughput goals, and expenses.\n\n'
      'Formatting and readability rules for mobile screens:\n'
      '- Make generous use of newlines, empty lines, and indents to keep responses airy and effortless to read.\n'
      '- NEVER cram multiple metrics or distinct ideas into one long sentence or dense paragraph.\n'
      '- NEVER cram multiple attributes onto the same line separated by pipes (do NOT do: "Target: X | Actual: Y"). Put each attribute on its own indented line.\n'
      '- NEVER use Markdown tables (e.g. | Col 1 | Col 2 |). Mobile screens are narrow, and tables cause horizontal scrolling and confusion.\n'
      '- Use bold text for key figures, metrics, and amounts (e.g. **₱12,500.00**, **4 Pending Deliveries**).\n'
      '- When presenting lists of stores, products, or breakdowns, format each as a clean vertical card with indented attributes (using Markdown list bullets "- ") and an empty line between cards:\n'
      '  Example format:\n'
      '  🏪 **7-Eleven Bayanihan**\n'
      '  - **Target**: ₱15,000\n'
      '  - **Actual Sales**: ₱16,200 (+8%)\n'
      '  - **Status**: ✅ Hit Target\n'
      '    - **PJP Visit**: Visited\n\n'
      '  🏪 **Mini Stop Poblacion**\n'
      '  - **Target**: ₱12,000\n'
      '  - **Actual Sales**: ₱9,500 (-21%)\n'
      '  - **Status**: ⚠️ Needs Follow-up\n\n'
      '- For KPI summaries or operational updates, group by topic with a short bold header and separate each metric on its own indented line:\n'
      '  📊 **Sales Overview**\n'
      '  - **Total Buying Sales**: ₱125,000\n'
      '  - **Buying Throughput**: 82%\n\n'
      '  🚚 **Deliveries**\n'
      '  - **Pending Deliveries**: 4 orders\n'
      '  - **Returned**: 1 order\n\n'
      '- Separate paragraphs, sections, and card blocks with a full blank line.\n'
      '- At the end of every helpful response, provide 2 or 3 quick suggested follow-up questions under a line starting with: "💡 Suggested questions:" with bullet points so the user can easily tap to explore further.'
      '${contextPrompt != null ? "\n\nCurrent operational context:\n$contextPrompt" : ""}',
    );

    _model = GenerativeModel(
      model: modelName,
      apiKey: key,
      systemInstruction: systemInstruction,
    );

    return _model;
  }

  /// Starts a fresh multi-turn chat session with operational context.
  Future<ChatSession?> startChat({String? contextPrompt}) async {
    _cachedContextPrompt = contextPrompt;
    final model = await getModel(contextPrompt: contextPrompt, modelIndex: _activeModelIndex);
    if (model == null) return null;
    _chatSession = model.startChat();
    return _chatSession;
  }

  bool _isOverloadedError(dynamic e) {
    final errStr = e.toString().toLowerCase();
    return errStr.contains('high demand') ||
        errStr.contains('overloaded') ||
        errStr.contains('503') ||
        errStr.contains('resourceexhausted') ||
        errStr.contains('try again later');
  }

  /// Sends a message in the active chat session after validating quota,
  /// with transparent fallback and retry across candidate models on high demand.
  Future<String> sendMessage(String userMessage) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }

    if (_chatSession == null) {
      await startChat(contextPrompt: _cachedContextPrompt);
    }

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        if (_chatSession == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final response = await _chatSession!.sendMessage(Content.text(userMessage));
        await recordAiUsage();
        return response.text ?? 'No response received from Gemini.';
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          // Failover to next candidate model
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          await startChat(contextPrompt: _cachedContextPrompt);
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please tap send again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Unable to reach Google Gemini. Please try again.');
  }

  /// Single-turn prompt generation with automatic failover.
  Future<String> generateText(String prompt, {String? contextPrompt}) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(contextPrompt: contextPrompt, modelIndex: _activeModelIndex);
        if (model == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final response = await model.generateContent([Content.text(prompt)]);
        await recordAiUsage();
        return response.text ?? 'No response generated.';
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Unable to generate response. Please try again.');
  }

  /// Extracts purchase order details, invoice number, date, and product quantities from one or multiple images/screenshots,
  /// matching abbreviated or altered product names against the active inventory catalog,
  /// utilizing confirmed supplier aliases and price verification.
  Future<ExtractedPurchaseOrderData> extractPurchaseOrderFromImages({
    required List<Uint8List> imagesBytesList,
    List<String>? mimeTypes,
    required List<InventoryItem> catalog,
    List<SupplierProductMapping>? knownMappings,
  }) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }
    if (imagesBytesList.isEmpty) {
      throw Exception('No document images provided for analysis.');
    }

    final catalogLines = catalog.map((item) {
      final codePart = item.itemCode.isNotEmpty ? ' | Code: "${item.itemCode}"' : '';
      return '- ID: "${item.id}"$codePart | Name: "${item.productName}" | Source: "${item.source.key}" | Cost: ₱${item.buyingPrice.toStringAsFixed(2)} | Category: "${item.category}"';
    }).join('\n');

    final singleMappings = (knownMappings ?? []).where((m) => !m.isMultiMatch).toList();
    final multiMappings = (knownMappings ?? []).where((m) => m.isMultiMatch).toList();

    final buffer = StringBuffer();
    if (singleMappings.isNotEmpty) {
      buffer.writeln('CONFIRMED SINGLE-PRODUCT SUPPLIER ALIASES (Learned & Verified by Dealer):');
      buffer.writeln('If the invoice description matches or starts with any of these, use the corresponding product ID immediately:');
      for (final m in singleMappings.take(30)) {
        buffer.writeln('• "${m.rawSupplierText}" -> ID: "${m.productId}" (${m.productName})');
      }
      buffer.writeln();
    }

    if (multiMappings.isNotEmpty) {
      final Map<String, InventoryItem> catalogById = {for (final item in catalog) item.id: item};
      buffer.writeln('KNOWN MULTI-VARIANT SUPPLIER ALIASES (Truncated descriptions with multiple Selecta flavors):');
      buffer.writeln('The following raw invoice texts are known to represent more than one distinct Selecta product:');
      for (final m in multiMappings.take(20)) {
        final variantNames = m.candidateProductIds
            .map((cid) => catalogById[cid]?.productName ?? cid)
            .join(' OR ');
        final idsJson = jsonEncode(m.candidateProductIds);
        buffer.writeln('• "${m.rawSupplierText}":');
        buffer.writeln('   - Possible Variants: $variantNames');
        buffer.writeln('   - Candidate IDs: $idsJson');
        buffer.writeln('   - MULTIMODAL INSTRUCTION: Check the product thumbnail image on the invoice (Option C). If lid/foil color identifies the flavor, output that exact product ID in "items". If no thumbnail or unclear, place in "ambiguous_items" with "candidate_product_ids": $idsJson.');
      }
      buffer.writeln();
    }

    final mappingsSection = buffer.toString();

    // Pre-process images: Automatically slice long scrolling screenshots into high-res chunks
    final List<Uint8List> processedBytesList = [];
    final List<String> processedMimeTypes = [];

    for (int i = 0; i < imagesBytesList.length; i++) {
      final originalBytes = imagesBytesList[i];
      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(originalBytes);
      if (slices.length > 1) {
        for (final slice in slices) {
          processedBytesList.add(slice);
          processedMimeTypes.add('image/png');
        }
      } else {
        processedBytesList.add(originalBytes);
        final mime = (mimeTypes != null && i < mimeTypes.length) ? mimeTypes[i] : 'image/jpeg';
        processedMimeTypes.add(mime);
      }
    }

    final isMulti = processedBytesList.length > 1;

    final prompt = '''
You are an expert OCR, purchasing, and inventory AI assistant for a Selecta ice cream dealership in the Philippines.
You are inspecting ${isMulti ? '${processedBytesList.length} sequential screenshots or document pages' : 'an image'} of a supplier Sales Invoice, Purchase Order, Delivery Receipt, or digital ordering screenshot.

${isMulti ? '''
MULTI-SCREENSHOT / MULTI-PAGE RULES:
1. The images provided are sequential screenshots (e.g. Page 1, Page 2, etc.) of the SAME order.
2. Read and extract all items across ALL screenshots in the continuous top-to-bottom sequence they appear.
3. PREVENT DUPLICATES FROM OVERLAPS: If adjacent screenshots overlap (e.g. the last row of Page 1 is repeated as the first row of Page 2), do NOT output that item twice! Detect identical rows at boundaries and output them only once.
''' : ''}

YOUR OBJECTIVES:
1. Extract the Invoice/Receipt Number (e.g. "HM30471505", "INV-12345"). If not present, leave empty.
2. Extract the Invoice/Order Date in YYYY-MM-DD format. If not present, leave null.
3. Extract the total invoice or order monetary amount (numeric value). If not present, set 0.0.
4. Extract all ordered or delivered items and their quantities.

$mappingsSection
CRITICAL QUANTITY & NUMBER EXTRACTION RULES:
1. QUANTITY COLUMN SELECTION:
   - Always extract the actual invoiced, shipped, or delivered quantity (the quantity being charged).
   - If there are multiple quantity columns (e.g. Ordered vs Delivered / Invoiced), choose the DELIVERED / INVOICED quantity.
   - Do NOT confuse unit price (e.g. ₱45.00), total line amount, or Item Code (e.g. 68021) with quantity.
2. UNIT OF MEASURE (Cases vs Pieces):
   - Check if quantities are given in cases (CS / BOX) or individual units (PC / PCS). Extract the primary count displayed on the line item.
3. DIGIT CLARITY:
   - Carefully distinguish visually similar characters (1 vs 7, 3 vs 8, 5 vs 6, 0 vs 8).

CRITICAL PRODUCT MATCHING RULES:
1. TRUNCATIONS, ABBREVIATIONS & ELLIPSIS:
   - Supplier systems regularly truncate product descriptions at column boundaries (e.g., ending with "...", "…", or cutting off mid-word like "MAGNUM CLASS...", "CORNETTO DISC WH...").
   - Use the unit price / line cost on the receipt: match it against the catalog Cost to distinguish sizes (e.g. Pint at ~₱105 vs Tub at ~₱225, or Cornetto vs Magnum).
   - If a supplier product code / SKU is printed on the invoice, match it against "Code" in the ACTIVE CATALOG.

2. MULTIMODAL THUMBNAIL PACKAGING COLOR & GRAPHICS (OPTION C):
   - In digital ordering apps and modern invoices, each row displays a thumbnail photo of the actual ice cream packaging.
   - Inspect visual packaging details to disambiguate truncated descriptions:
     * Cones (Cornetto): Look at the cone top lid disc color and foil wrapper (e.g. WHITE lid disc for Cornetto Disc White, BROWN/CHOCOLATE lid disc for Cornetto Disc Chocolate, RED lid for Strawberry, BLUE for Cookies & Dream).
     * Sticks (Magnum/Solero): Look at wrapper foil color (e.g. gold foil for Magnum Almond, dark brown/red for Magnum Classic, green for Solero Lime).
     * Tubs / Pints: Inspect tub rim color, flavor banner, or label artwork.
   - If the thumbnail packaging photo clearly reveals the exact flavor/variant, assign that specific product ID in "items" with confidence >= 0.95.

3. COLLIDING TRUNCATED ITEMS & MULTI-MATCH VARIANTS:
   - In supplier invoices, the SAME product is almost NEVER listed on two separate rows.
   - If two or more separate rows have the SAME or nearly identical truncated text ending in "..." or "…" (e.g. two separate rows both showing "CORNETTO DISC..."):
     THEY ARE DIFFERENT FLAVORS / VARIANTS!
     DO NOT assign both rows to the same catalog product!
     - First, look at packaging thumbnail color, item code, or unit price differences to distinguish the variants.
     - If you cannot be 100% sure which variant is which, place BOTH rows into "ambiguous_items" with candidate product IDs.
   - If a row has truncated text that matches a KNOWN MULTI-VARIANT ALIAS (or could be 2+ variants):
     - If the thumbnail packaging reveals the flavor, output it in "items".
     - If NO thumbnail is visible or the packaging is ambiguous: DO NOT GUESS RANDOMLY! Place it in "ambiguous_items" with the candidate product IDs so the dealer can clarify with 1 tap.

4. CONFIDENCE & AMBIGUITY:
   - If you are confident (confidence >= 0.85) in the exact product, place it in "items".
   - If a line item is truncated with ellipsis or could plausibly be one of multiple catalog items:
     Place it in "ambiguous_items" with:
     - "raw_text": exact printed text on the receipt
     - "quantity": quantity ordered/delivered
     - "detected_unit_price": unit buying price if visible (0.0 if not)
     - "candidate_product_ids": [array of 2 to 4 potential matching product IDs from catalog]
     - "reason": brief explanation (e.g. "Truncated name with multiple Cornetto variants")
   - If a line item clearly cannot be matched to any ice cream product (e.g. pallet deposit, delivery fee), place it in "unmatched_items".

ACTIVE CATALOG:
$catalogLines

CRITICAL: Respond ONLY with a valid JSON object matching this schema (do NOT include commentary outside JSON):
{
  "invoice_number": "HM30471505",
  "invoice_date": "2026-10-01",
  "total_amount": 12500.00,
  "items": [
    {
      "product_id": "exact-catalog-id",
      "matched_product_name": "exact-catalog-name",
      "raw_text": "text seen on invoice",
      "quantity": 10,
      "confidence": 0.95
    }
  ],
  "ambiguous_items": [
    {
      "raw_text": "CORNETTO DISC WH...",
      "quantity": 24,
      "detected_unit_price": 32.50,
      "candidate_product_ids": ["candidate-id-1", "candidate-id-2"],
      "reason": "Truncated name with multiple possible flavors"
    }
  ],
  "unmatched_items": [
    {
      "raw_text": "unmatched item text",
      "quantity": 5
    }
  ]
}
''';

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(modelIndex: _activeModelIndex);
        if (model == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final parts = <Part>[TextPart(prompt)];
        for (int i = 0; i < processedBytesList.length; i++) {
          parts.add(DataPart(processedMimeTypes[i], processedBytesList[i]));
        }

        final content = [Content.multi(parts)];

        final response = await model.generateContent(content);
        await recordAiUsage();
        final rawText = response.text ?? '';
        return _parseExtractedPurchaseOrderData(rawText, catalog, knownMappings);
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Failed to process invoice images.');
  }

  /// Single image convenience method
  Future<ExtractedPurchaseOrderData> extractPurchaseOrderFromImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    required List<InventoryItem> catalog,
    List<SupplierProductMapping>? knownMappings,
  }) {
    return extractPurchaseOrderFromImages(
      imagesBytesList: [imageBytes],
      mimeTypes: [mimeType],
      catalog: catalog,
      knownMappings: knownMappings,
    );
  }

  /// Extracts a store order (product names + quantities) from one or more screenshots/photos
  /// of a receipt generated by an external order-booking app, matching each line against
  /// the active inventory catalog. Reuses [ExtractedPurchaseOrderData] so callers can share
  /// the same disambiguation flow as purchase orders.
  Future<ExtractedPurchaseOrderData> extractStoreOrderFromImages({
    required List<Uint8List> imagesBytesList,
    List<String>? mimeTypes,
    required List<InventoryItem> catalog,
    List<SupplierProductMapping>? knownMappings,
  }) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }
    if (imagesBytesList.isEmpty) {
      throw Exception('No receipt images provided for analysis.');
    }

    final catalogLines = catalog.map((item) {
      final codePart = item.itemCode.isNotEmpty ? ' | Code: "${item.itemCode}"' : '';
      return '- ID: "${item.id}"$codePart | Name: "${item.productName}" | Source: "${item.source.key}" | SRP: ₱${item.sellingPrice.toStringAsFixed(2)} | Category: "${item.category}"';
    }).join('\n');

    final Map<String, InventoryItem> catalogById = {for (final item in catalog) item.id: item};
    final aliasBuffer = StringBuffer();
    final mappings = knownMappings ?? [];
    final singleMappings = mappings.where((m) => !m.isMultiMatch).toList();
    final multiMappings = mappings.where((m) => m.isMultiMatch).toList();
    if (singleMappings.isNotEmpty) {
      aliasBuffer.writeln('CONFIRMED BOOKING-APP ALIASES (Learned & Verified by the user):');
      aliasBuffer.writeln('If a receipt line matches or starts with any of these, use the corresponding product ID immediately:');
      for (final m in singleMappings.take(40)) {
        aliasBuffer.writeln('• "${m.rawSupplierText}" -> ID: "${m.productId}" (${m.productName})');
      }
      aliasBuffer.writeln();
    }
    if (multiMappings.isNotEmpty) {
      aliasBuffer.writeln('KNOWN MULTI-VARIANT BOOKING-APP ALIASES (one receipt name maps to several catalog products):');
      for (final m in multiMappings.take(20)) {
        final variantNames = m.candidateProductIds.map((cid) => catalogById[cid]?.productName ?? cid).join(' OR ');
        aliasBuffer.writeln('• "${m.rawSupplierText}" -> $variantNames | Candidate IDs: ${jsonEncode(m.candidateProductIds)}');
        aliasBuffer.writeln('   - Unless the receipt clearly identifies the variant, place it in "ambiguous_items" with these candidate IDs.');
      }
      aliasBuffer.writeln();
    }

    // Pre-process images: Automatically slice long scrolling screenshots into high-res chunks
    final List<Uint8List> processedBytesList = [];
    final List<String> processedMimeTypes = [];
    for (int i = 0; i < imagesBytesList.length; i++) {
      final originalBytes = imagesBytesList[i];
      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(originalBytes);
      if (slices.length > 1) {
        for (final slice in slices) {
          processedBytesList.add(slice);
          processedMimeTypes.add('image/png');
        }
      } else {
        processedBytesList.add(originalBytes);
        processedMimeTypes.add((mimeTypes != null && i < mimeTypes.length) ? mimeTypes[i] : 'image/jpeg');
      }
    }

    final isMulti = processedBytesList.length > 1;

    final prompt = '''
You are an expert OCR and sales-order AI assistant for a Selecta ice cream dealership in the Philippines.
You are inspecting ${isMulti ? '${processedBytesList.length} sequential screenshots or photos' : 'an image'} of an ORDER RECEIPT / ORDER SUMMARY
generated by a separate order-booking app. It lists the products a retail store (Hapi Store) ordered and their quantities.

${isMulti ? '''
MULTI-SCREENSHOT RULES:
1. The images are sequential parts of the SAME order. Read all items top-to-bottom across ALL images.
2. PREVENT DUPLICATES FROM OVERLAPS: If adjacent screenshots overlap and repeat the same row at the boundary, output it only once.
''' : ''}
YOUR OBJECTIVES:
1. Extract every ordered product line and its ordered quantity.
2. If an order/reference number is visible, put it in "invoice_number" (else empty). If an order date is visible, put it in "invoice_date" as YYYY-MM-DD (else null).
3. If a grand total is visible, put it in "total_amount" (else 0.0).

$aliasBuffer
QUANTITY RULES:
- Extract the ORDERED quantity for each line. Do NOT confuse prices, line totals, item codes, or line numbers with quantity.
- Carefully distinguish visually similar digits (1 vs 7, 3 vs 8, 5 vs 6, 0 vs 8).
- If the same product appears on multiple rows, output each row separately (the app will merge them).

PRODUCT MATCHING RULES:
- The booking app may use different naming, abbreviations, or size wording than our catalog (e.g. "Selecta Cornetto Classic Vanilla" vs "CORNETTO CLASSIC VANILLA 110ML").
- Match by brand, product line, flavor, AND size/pack (pint vs tub vs half-gallon, piece vs case). Size and pack must agree.
- Only place an item in "items" when confidence >= 0.85.
- If a line could plausibly be 2+ catalog products, place it in "ambiguous_items" with 2-4 "candidate_product_ids" and a brief "reason".
- If a line is clearly not a catalog product (e.g. delivery fee, discount, subtotal), place it in "unmatched_items".
- Ignore subtotal, tax, discount, and total rows as product lines.

ACTIVE CATALOG:
$catalogLines

CRITICAL: Respond ONLY with a valid JSON object matching this schema (no commentary outside JSON):
{
  "invoice_number": "",
  "invoice_date": null,
  "total_amount": 0.0,
  "items": [
    {
      "product_id": "exact-catalog-id",
      "matched_product_name": "exact-catalog-name",
      "raw_text": "text seen on receipt",
      "quantity": 10,
      "confidence": 0.95
    }
  ],
  "ambiguous_items": [
    {
      "raw_text": "text seen on receipt",
      "quantity": 4,
      "detected_unit_price": 0.0,
      "candidate_product_ids": ["candidate-id-1", "candidate-id-2"],
      "reason": "Multiple possible sizes"
    }
  ],
  "unmatched_items": [
    { "raw_text": "unmatched line text", "quantity": 1 }
  ]
}
''';

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(modelIndex: _activeModelIndex);
        if (model == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final parts = <Part>[TextPart(prompt)];
        for (int i = 0; i < processedBytesList.length; i++) {
          parts.add(DataPart(processedMimeTypes[i], processedBytesList[i]));
        }

        final response = await model.generateContent([Content.multi(parts)]);
        await recordAiUsage();
        return _parseExtractedPurchaseOrderData(response.text ?? '', catalog, knownMappings);
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }
        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Failed to process receipt images.');
  }

  /// Compares one or more official paper invoice images against the original PO items.
  /// Returns which items were confirmed (possibly with adjusted quantities) and which
  /// are missing (out of stock from supplier), along with the invoice total and number.
  Future<InvoiceComparisonResult> compareOfficialInvoiceWithPoItems({
    required List<Uint8List> invoiceImagesBytesList,
    required List<String> mimeTypes,
    required List<OrderItem> originalPoItems,
    required String originalPoNumber,
  }) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }

    // Pre-process images: Automatically slice long scrolling screenshots or receipts
    final List<Uint8List> processedBytesList = [];
    final List<String> processedMimeTypes = [];

    for (int i = 0; i < invoiceImagesBytesList.length; i++) {
      final originalBytes = invoiceImagesBytesList[i];
      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(originalBytes);
      if (slices.length > 1) {
        for (final slice in slices) {
          processedBytesList.add(slice);
          processedMimeTypes.add('image/png');
        }
      } else {
        processedBytesList.add(originalBytes);
        final mime = i < mimeTypes.length ? mimeTypes[i] : 'image/jpeg';
        processedMimeTypes.add(mime);
      }
    }

    // Build the original PO manifest for the prompt
    final poLines = originalPoItems.map((item) {
      return '- ID: "${item.productId}" | Name: "${item.productName}" | Ordered Qty: ${item.orderedQuantity} | Unit Cost: ${item.buyingPrice}';
    }).join('\n');

    final prompt = '''
You are an expert purchasing and inventory AI assistant for a Selecta ice cream dealership in the Philippines.
You are comparing an official supplier invoice (paper copy) against a digital purchase order (PO) that was previously placed.

ORIGINAL PURCHASE ORDER: $originalPoNumber
$poLines

YOUR TASK:
1. Read the official invoice image(s) carefully.
2. For each item in the ORIGINAL PO, determine if it appears on the official invoice:
   - If YES (it arrived): include it in "confirmed_items" with the ACTUAL quantity from the official invoice.
   - If NO (it is absent / out of stock): include its ID in "missing_product_ids".
3. Extract the total invoice amount (numeric).
4. Extract the official invoice number / reference code.

CRITICAL MATCHING RULES:
- Invoice may use abbreviations (e.g. "CORN CHOC" for "Cornetto Chocolate"). Match by context.
- Always use the exact product_id from the ORIGINAL PO.
- The quantity on the official invoice (actual delivered) may differ from the ordered quantity — use the invoice quantity.

CRITICAL: Respond ONLY with a valid JSON object (no commentary outside JSON):
{
  "invoice_number": "HM30471505",
  "invoice_date": "2026-10-01",
  "total_amount": 12500.00,
  "confirmed_items": [
    {
      "product_id": "exact-po-product-id",
      "product_name": "exact product name from PO",
      "delivered_quantity": 10,
      "unit_cost": 45.00
    }
  ],
  "missing_product_ids": ["product-id-1", "product-id-2"]
}
''';

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(modelIndex: _activeModelIndex);
        if (model == null) throw Exception('Failed to initialize AI model session.');

        // Build multipart content with all invoice images
        final parts = <Part>[TextPart(prompt)];
        for (int i = 0; i < processedBytesList.length; i++) {
          parts.add(DataPart(processedMimeTypes[i], processedBytesList[i]));
        }

        final response = await model.generateContent([Content.multi(parts)]);
        await recordAiUsage();
        final rawText = response.text ?? '';
        return _parseInvoiceComparisonResult(rawText, originalPoItems);
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }
        if (_isOverloadedError(e)) {
          throw Exception('Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.');
        }
        rethrow;
      }
    }

    throw Exception('Unable to compare official invoice with PO. Please try again.');
  }

  InvoiceComparisonResult _parseInvoiceComparisonResult(String rawText, List<OrderItem> originalPoItems) {
    if (rawText.trim().isEmpty) {
      return InvoiceComparisonResult(confirmedItems: const [], missingItems: originalPoItems);
    }

    String cleaned = rawText.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3).trim();
    }
    final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);
    if (jsonMatch != null) cleaned = jsonMatch.group(0)!;

    try {
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      final invoiceNumber = (decoded['invoice_number'] as String? ?? '').trim();
      final totalAmount = (decoded['total_amount'] as num?)?.toDouble() ?? 0.0;

      DateTime? invoiceDate;
      final dateStr = decoded['invoice_date'] as String?;
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        try { invoiceDate = DateTime.parse(dateStr.trim()); } catch (_) {}
      }

      // Build a map of original PO items by ID for quick lookup
      final Map<String, OrderItem> poById = {for (final item in originalPoItems) item.productId: item};

      // Parse confirmed items
      final List<ConfirmedInvoiceItem> confirmedItems = [];
      final rawConfirmed = decoded['confirmed_items'] as List<dynamic>? ?? [];
      for (final raw in rawConfirmed) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final productId = (map['product_id'] as String? ?? '').trim();
        final deliveredQty = (map['delivered_quantity'] as num?)?.toInt() ?? 0;
        if (productId.isEmpty || deliveredQty <= 0) continue;
        final poItem = poById[productId];
        if (poItem != null) {
          confirmedItems.add(ConfirmedInvoiceItem(
            productId: productId,
            productName: poItem.productName,
            orderedQuantity: poItem.orderedQuantity,
            deliveredQuantity: deliveredQty,
            unitCost: poItem.buyingPrice,
            imageUrl: poItem.imageUrl,
            productSource: poItem.productSource,
            category: poItem.category,
            tag: poItem.tag,
            sellingPrice: poItem.sellingPrice,
          ));
        }
      }

      // Parse missing product IDs
      final rawMissingIds = decoded['missing_product_ids'] as List<dynamic>? ?? [];
      final Set<String> missingIdSet = rawMissingIds.map((e) => e.toString().trim()).toSet();

      // Build missing items list from original PO
      final List<OrderItem> missingItems = originalPoItems
          .where((item) => missingIdSet.contains(item.productId))
          .toList();

      // Any items from original PO not accounted for in confirmed or missing => treat as missing
      final confirmedIds = confirmedItems.map((e) => e.productId).toSet();
      for (final item in originalPoItems) {
        if (!confirmedIds.contains(item.productId) && !missingIdSet.contains(item.productId)) {
          missingItems.add(item);
        }
      }

      return InvoiceComparisonResult(
        invoiceNumber: invoiceNumber,
        invoiceDate: invoiceDate,
        totalAmount: totalAmount,
        confirmedItems: confirmedItems,
        missingItems: missingItems,
        rawAiResponse: rawText,
      );
    } catch (_) {
      // Fallback: all items are unconfirmed
      return InvoiceComparisonResult(
        confirmedItems: const [],
        missingItems: originalPoItems,
        rawAiResponse: rawText,
      );
    }
  }

  ExtractedPurchaseOrderData _parseExtractedPurchaseOrderData(
    String rawText,
    List<InventoryItem> catalog, [
    List<SupplierProductMapping>? knownMappings,
  ]) {
    if (rawText.trim().isEmpty) {
      return const ExtractedPurchaseOrderData();
    }

    String cleaned = rawText.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }
    }

    // Try finding JSON block between { and }
    final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);
    if (jsonMatch != null) {
      cleaned = jsonMatch.group(0)!;
    }

    try {
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      final invoiceNumber = (decoded['invoice_number'] as String? ?? '').trim();
      DateTime? invoiceDate;
      final dateStr = decoded['invoice_date'] as String?;
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        try {
          invoiceDate = DateTime.parse(dateStr.trim());
        } catch (_) {}
      }

      final totalAmount = (decoded['total_amount'] as num?)?.toDouble() ?? 0.0;

      final Map<String, InventoryItem> catalogById = {for (final item in catalog) item.id: item};
      final Map<String, InventoryItem> catalogByName = {
        for (final item in catalog) item.productName.trim().toLowerCase(): item
      };

      final List<ExtractedPoItem> matchedItems = [];
      final rawItems = decoded['items'] as List<dynamic>? ?? [];

      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final productId = (map['product_id'] as String? ?? '').trim();
        final matchedName = (map['matched_product_name'] as String? ?? '').trim();
        final rawTextItem = (map['raw_text'] as String? ?? matchedName).trim();
        final qty = (map['quantity'] as num?)?.toInt() ?? 0;
        final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.9;

        if (qty <= 0) continue;

        // Verify ID against catalog
        InventoryItem? matchedItem = catalogById[productId];
        if (matchedItem == null && matchedName.isNotEmpty) {
          matchedItem = catalogByName[matchedName.toLowerCase()];
        }

        if (matchedItem != null) {
          matchedItems.add(
            ExtractedPoItem(
              productId: matchedItem.id,
              matchedProductName: matchedItem.productName,
              rawText: rawTextItem,
              quantity: qty,
              confidence: confidence,
            ),
          );
        }
      }

      final List<AmbiguousPoItem> ambiguousItems = [];
      final rawAmbiguous = decoded['ambiguous_items'] as List<dynamic>? ?? [];

      for (final raw in rawAmbiguous) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final rawTextItem = (map['raw_text'] as String? ?? '').trim();
        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final price = (map['detected_unit_price'] as num?)?.toDouble() ?? 0.0;
        final reason = (map['reason'] as String? ?? '').trim();
        final candidateIds = (map['candidate_product_ids'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .where((id) => catalogById.containsKey(id))
            .toList();

        if (qty <= 0) continue;

        // Check if we have a confirmed mapping for this rawText
        SupplierProductMapping? learnedMatch;
        if (knownMappings != null && rawTextItem.isNotEmpty) {
          final targetNorm = SupplierProductMapping.normalize(rawTextItem);
          for (final m in knownMappings) {
            if (m.normalizedText == targetNorm ||
                (targetNorm.length >= 6 &&
                    (m.normalizedText.startsWith(targetNorm) ||
                        targetNorm.startsWith(m.normalizedText)))) {
              learnedMatch = m;
              break;
            }
          }
        }

        if (learnedMatch != null && !learnedMatch.isMultiMatch && catalogById.containsKey(learnedMatch.productId)) {
          final inv = catalogById[learnedMatch.productId]!;
          matchedItems.add(
            ExtractedPoItem(
              productId: inv.id,
              matchedProductName: inv.productName,
              rawText: rawTextItem,
              quantity: qty,
              confidence: 1.0,
            ),
          );
        } else {
          final Set<String> combinedCandidates = {};
          if (learnedMatch != null && learnedMatch.isMultiMatch) {
            combinedCandidates.addAll(learnedMatch.candidateProductIds);
          }
          combinedCandidates.addAll(candidateIds);
          final validCandidates = combinedCandidates.where((id) => catalogById.containsKey(id)).toList();

          ambiguousItems.add(
            AmbiguousPoItem(
              rawText: rawTextItem,
              quantity: qty,
              detectedUnitPrice: price,
              candidateProductIds: validCandidates,
              reason: (learnedMatch != null && learnedMatch.isMultiMatch)
                  ? 'Known multi-variant supplier alias with ${validCandidates.length} options'
                  : reason,
            ),
          );
        }
      }

      final List<String> unmatchedItems = [];
      final rawUnmatched = decoded['unmatched_items'] as List<dynamic>? ?? [];
      for (final raw in rawUnmatched) {
        if (raw is Map) {
          final t = (raw['raw_text'] as String? ?? '').trim();
          final q = (raw['quantity'] as num?)?.toInt();
          if (t.isNotEmpty) {
            unmatchedItems.add(q != null && q > 0 ? '$t (Qty: $q)' : t);
          }
        } else if (raw is String && raw.trim().isNotEmpty) {
          unmatchedItems.add(raw.trim());
        }
      }

      return ExtractedPurchaseOrderData(
        invoiceNumber: invoiceNumber,
        invoiceDate: invoiceDate,
        totalAmount: totalAmount,
        matchedItems: matchedItems,
        ambiguousItems: ambiguousItems,
        unmatchedItems: unmatchedItems,
        rawAiResponse: rawText,
      );
    } catch (_) {
      return ExtractedPurchaseOrderData(rawAiResponse: rawText);
    }
  }

  /// Extracts supplier daily stock availability from one or multiple screenshots / documents,
  /// strictly matching against products that exist in the dealer's catalog (active or inactive).
  /// Excludes any products not in the dealer catalog.
  Future<ExtractedSupplierStockData> extractSupplierStockStatusFromImages({
    required List<Uint8List> imagesBytesList,
    List<String>? mimeTypes,
    required List<InventoryItem> dealerCatalog,
    List<SupplierProductMapping>? knownMappings,
  }) async {
    final status = await checkAiAvailability();
    if (!status.isAllowed) {
      throw Exception(status.message ?? 'AI Assistant is currently unavailable.');
    }
    if (imagesBytesList.isEmpty) {
      throw Exception('No supplier stock images provided for analysis.');
    }

    // Exclude other products: this feature is strictly exclusive to Selecta products
    final selectaCatalog = dealerCatalog
        .where((item) => item.source == InventoryProductSource.selecta)
        .toList();

    final catalogLines = selectaCatalog.map((item) {
      final codePart = item.itemCode.isNotEmpty ? ' | Code: "${item.itemCode}"' : '';
      return '- ID: "${item.id}"$codePart | Name: "${item.productName}" | Category: "${item.category}"';
    }).join('\n');

    final singleMappings = (knownMappings ?? []).where((m) => !m.isMultiMatch).toList();
    final buffer = StringBuffer();
    if (singleMappings.isNotEmpty) {
      buffer.writeln('CONFIRMED SUPPLIER ALIASES:');
      for (final m in singleMappings.take(30)) {
        buffer.writeln('• "${m.rawSupplierText}" -> ID: "${m.productId}" (${m.productName})');
      }
      buffer.writeln();
    }
    final mappingsSection = buffer.toString();

    final List<Uint8List> processedBytesList = [];
    final List<String> processedMimeTypes = [];
    for (int i = 0; i < imagesBytesList.length; i++) {
      final originalBytes = imagesBytesList[i];
      final slices = await ImageSlicingService.sliceIfScrollingScreenshot(originalBytes);
      if (slices.length > 1) {
        for (final slice in slices) {
          processedBytesList.add(slice);
          processedMimeTypes.add('image/png');
        }
      } else {
        processedBytesList.add(originalBytes);
        final mime = (mimeTypes != null && i < mimeTypes.length) ? mimeTypes[i] : 'image/jpeg';
        processedMimeTypes.add(mime);
      }
    }

    final isMulti = processedBytesList.length > 1;

    final prompt = '''
You are an expert purchasing and inventory AI assistant for a Selecta ice cream dealership.
You are inspecting ${isMulti ? '${processedBytesList.length} sequential screenshots or document pages' : 'an image'} of a supplier stock availability list, warehouse stock report, or distributor portal snapshot.

YOUR OBJECTIVES:
1. Extract the Report Date in YYYY-MM-DD format if visible (e.g. at the top or header). If not present, output null.
2. STRICT MATCHING WITH DEALER SELECTA CATALOG ONLY:
   CRITICAL REQUIREMENT: The supplier document will contain many products that DO NOT exist in the dealer's inventory.
   You MUST ONLY match and output items that exist in the DEALER SELECTA CATALOG below!
   Do NOT output or invent items that are not in the DEALER SELECTA CATALOG. Ignore all other items.

3. DETERMINE STOCK STATUS FOR EACH MATCHED ITEM:
   - "is_out_of_stock": true IF the row indicates no stock, 0 quantity, "OOS", "Out of Stock", "Not Available", "Zero", crossed out, or highlighted as unavailable.
   - "is_out_of_stock": false IF the supplier indicates available stock, positive quantity, or standard available status.
   - "supplier_quantity": numeric available quantity if specified (e.g. 50, 120), or null if unstated.

$mappingsSection
DEALER SELECTA CATALOG (Active & Inactive products):
$catalogLines

CRITICAL: Respond ONLY with a valid JSON object matching this schema (do NOT include markdown or text outside JSON):
{
  "report_date": "2026-10-06",
  "matched_items": [
    {
      "product_id": "exact-dealer-catalog-id",
      "matched_product_name": "exact-dealer-catalog-name",
      "raw_text": "text seen on supplier document",
      "is_out_of_stock": false,
      "supplier_quantity": 45
    }
  ],
  "out_of_stock_product_ids": [
    "exact-dealer-catalog-id"
  ]
}
''';

    for (int attempt = 0; attempt < _candidateModels.length; attempt++) {
      try {
        final model = await getModel(modelIndex: _activeModelIndex);
        if (model == null) {
          throw Exception('Failed to initialize AI model session.');
        }

        final parts = <Part>[TextPart(prompt)];
        for (int i = 0; i < processedBytesList.length; i++) {
          parts.add(DataPart(processedMimeTypes[i], processedBytesList[i]));
        }

        final content = [Content.multi(parts)];
        final response = await model.generateContent(content);
        await recordAiUsage();
        final rawText = response.text ?? '';
        return _parseExtractedSupplierStockData(rawText, selectaCatalog);
      } catch (e) {
        if (_isOverloadedError(e) && attempt < _candidateModels.length - 1) {
          _activeModelIndex = (_activeModelIndex + 1) % _candidateModels.length;
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        if (_isOverloadedError(e)) {
          throw Exception(
            'Google Gemini servers are temporarily experiencing high demand. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    throw Exception('Failed to process supplier stock images.');
  }

  ExtractedSupplierStockData _parseExtractedSupplierStockData(
    String rawText,
    List<InventoryItem> dealerCatalog,
  ) {
    try {
      var cleaned = rawText.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3).trim();
        }
      }
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);
      if (jsonMatch != null) {
        cleaned = jsonMatch.group(0)!;
      }
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      DateTime? reportDate;
      final rawDate = decoded['report_date'] as String?;
      if (rawDate != null && rawDate.isNotEmpty) {
        reportDate = DateTime.tryParse(rawDate);
      }

      final Map<String, InventoryItem> catalogById = {
        for (final item in dealerCatalog) item.id: item
      };
      final Map<String, InventoryItem> catalogByName = {
        for (final item in dealerCatalog) item.productName.toLowerCase(): item
      };

      final List<SupplierStockItemStatus> matchedItems = [];
      final Set<String> outOfStockIds = {};
      final Set<String> inStockIds = {};

      final rawMatched = decoded['matched_items'] as List<dynamic>? ?? [];
      for (final raw in rawMatched) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final productId = (map['product_id'] as String? ?? '').trim();
        final matchedName = (map['matched_product_name'] as String? ?? '').trim();
        final rawTextItem = (map['raw_text'] as String? ?? matchedName).trim();
        final isOos = map['is_out_of_stock'] == true;
        final supplierQty = (map['supplier_quantity'] as num?)?.toInt();

        InventoryItem? matchedItem = catalogById[productId];
        if (matchedItem == null && matchedName.isNotEmpty) {
          matchedItem = catalogByName[matchedName.toLowerCase()];
        }

        if (matchedItem != null) {
          matchedItems.add(
            SupplierStockItemStatus(
              productId: matchedItem.id,
              matchedProductName: matchedItem.productName,
              rawText: rawTextItem,
              isOutOfStock: isOos,
              supplierAvailableQuantity: supplierQty,
            ),
          );
          if (isOos) {
            outOfStockIds.add(matchedItem.id);
          } else {
            inStockIds.add(matchedItem.id);
          }
        }
      }

      final rawOosList = decoded['out_of_stock_product_ids'] as List<dynamic>? ?? [];
      for (final rawId in rawOosList) {
        final idStr = rawId.toString().trim();
        if (catalogById.containsKey(idStr)) {
          outOfStockIds.add(idStr);
          inStockIds.remove(idStr);
        }
      }

      return ExtractedSupplierStockData(
        reportDate: reportDate,
        matchedItems: matchedItems,
        outOfStockProductIds: outOfStockIds.toList(),
        inStockProductIds: inStockIds.toList(),
        rawAiResponse: rawText,
      );
    } catch (_) {
      return ExtractedSupplierStockData(rawAiResponse: rawText);
    }
  }
}
