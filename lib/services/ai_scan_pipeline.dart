import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/services/ai/ai_provider_chain.dart';
import 'package:selecta_ops/services/ai/gemini_text_provider.dart';
import 'package:selecta_ops/services/ai/groq_text_provider.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/ocr/catalog_matcher.dart';
import 'package:selecta_ops/services/ocr/document_layout_parser.dart';
import 'package:selecta_ops/services/ocr/mlkit_ocr_engine.dart';
import 'package:selecta_ops/services/ocr/ocr_engine.dart';
import 'package:selecta_ops/services/supplier_mapping_service.dart';

/// Orchestrates zero-cost on-device OCR, document parsing, catalog matching,
/// and optional lightweight text LLM resolution for ambiguous items.
class AiScanPipeline {
  final OcrEngine ocrEngine;
  final AiProviderChain providerChain;
  final SupplierMappingService? mappingService;

  AiScanPipeline({
    OcrEngine? ocrEngine,
    AiProviderChain? providerChain,
    this.mappingService,
  })  : ocrEngine = ocrEngine ?? MlKitOcrEngine(),
        providerChain = providerChain ??
            AiProviderChain(
              providers: [
                GeminiTextProvider(
                  getApiKey: () => GeminiAiService().getEffectiveApiKeySync(),
                ),
                GroqTextProvider(
                  getApiKey: () => GeminiAiService().getEffectiveGroqApiKeySync(),
                ),
              ],
            );

  Future<List<SupplierProductMapping>> _fetchMappings() async {
    try {
      final service = mappingService ?? SupplierMappingService();
      return await service.getAllMappings();
    } catch (_) {
      return [];
    }
  }

  /// Executes Purchase Order / Delivery Receipt scanning.
  Future<ExtractedPurchaseOrderData> extractPurchaseOrder({
    required List<Uint8List> images,
    required List<InventoryItem> catalog,
    required String scanMode,
    List<String> providerOrder = const ['gemini', 'groq'],
    AiScanTimingTracker? tracker,
  }) async {
    final swOcr = Stopwatch()..start();
    final ocrResult = await ocrEngine.recognizeMultipleBytes(images);
    swOcr.stop();

    final swParse = Stopwatch()..start();
    final parsedDoc = PurchaseOrderParser.parse(ocrResult);
    swParse.stop();

    final swMatch = Stopwatch()..start();
    final mappings = await _fetchMappings();

    final matcher = CatalogMatcher(
      catalog: catalog,
      learnedMappings: mappings,
    );

    final rowMatches = <RowMatchResult>[];
    for (final row in parsedDoc.rows) {
      rowMatches.add(matcher.matchRow(row, isPurchaseOrder: true));
    }
    swMatch.stop();

    final unresolvedMatches = rowMatches.where((m) => !m.isResolved).toList();
    String rawLlmResponse = '';
    final swLlm = Stopwatch()..start();

    // Hybrid mode: call text LLM only if unresolved lines or missing header fields exist
    if (scanMode == 'hybrid' &&
        (unresolvedMatches.isNotEmpty ||
            parsedDoc.invoiceNumber.isEmpty ||
            parsedDoc.invoiceDate == null)) {
      try {
        final llmResult = await _resolveWithTextLlm(
          unresolvedMatches: unresolvedMatches,
          parsedDoc: parsedDoc,
          catalog: catalog,
          providerOrder: providerOrder,
        );
        rawLlmResponse = llmResult.rawResponse;

        // Merge LLM resolutions back into rowMatches
        _applyLlmResolutions(
          rowMatches: rowMatches,
          llmResolutions: llmResult.resolutions,
          catalog: catalog,
        );
      } catch (e) {
        debugPrint('AiScanPipeline: Hybrid text LLM step failed: $e. Falling back to local matches.');
      }
    }
    swLlm.stop();

    tracker?.recordPipelineTiming(
      ocrMs: swOcr.elapsedMilliseconds,
      parseMs: swParse.elapsedMilliseconds,
      matchMs: swMatch.elapsedMilliseconds,
      llmMs: swLlm.elapsedMilliseconds,
      unresolvedCount: unresolvedMatches.length,
      providerUsed: providerChain.lastUsedProviderId ?? 'none (local)',
    );

    return matcher.mapToPurchaseOrderData(
      parsedDoc,
      rowMatches,
      rawResponse: rawLlmResponse,
    );
  }

  /// Executes Store Order / Booking Receipt scanning.
  Future<ExtractedPurchaseOrderData> extractStoreOrder({
    required List<Uint8List> images,
    required List<InventoryItem> catalog,
    required String scanMode,
    List<String> providerOrder = const ['gemini', 'groq'],
    AiScanTimingTracker? tracker,
  }) async {
    final swOcr = Stopwatch()..start();
    final ocrResult = await ocrEngine.recognizeMultipleBytes(images);
    swOcr.stop();

    final swParse = Stopwatch()..start();
    final parsedDoc = StoreReceiptParser.parse(ocrResult);
    swParse.stop();

    final swMatch = Stopwatch()..start();
    final mappings = await _fetchMappings();

    final matcher = CatalogMatcher(
      catalog: catalog,
      learnedMappings: mappings,
    );

    final rowMatches = <RowMatchResult>[];
    for (final row in parsedDoc.rows) {
      rowMatches.add(matcher.matchRow(row, isPurchaseOrder: false));
    }
    swMatch.stop();

    final unresolvedMatches = rowMatches.where((m) => !m.isResolved).toList();
    String rawLlmResponse = '';
    final swLlm = Stopwatch()..start();

    if (scanMode == 'hybrid' && unresolvedMatches.isNotEmpty) {
      try {
        final llmResult = await _resolveWithTextLlm(
          unresolvedMatches: unresolvedMatches,
          parsedDoc: parsedDoc,
          catalog: catalog,
          providerOrder: providerOrder,
        );
        rawLlmResponse = llmResult.rawResponse;

        _applyLlmResolutions(
          rowMatches: rowMatches,
          llmResolutions: llmResult.resolutions,
          catalog: catalog,
        );
      } catch (e) {
        debugPrint('AiScanPipeline: Store receipt hybrid LLM step failed: $e');
      }
    }
    swLlm.stop();

    tracker?.recordPipelineTiming(
      ocrMs: swOcr.elapsedMilliseconds,
      parseMs: swParse.elapsedMilliseconds,
      matchMs: swMatch.elapsedMilliseconds,
      llmMs: swLlm.elapsedMilliseconds,
      unresolvedCount: unresolvedMatches.length,
      providerUsed: providerChain.lastUsedProviderId ?? 'none (local)',
    );

    return matcher.mapToPurchaseOrderData(
      parsedDoc,
      rowMatches,
      rawResponse: rawLlmResponse,
    );
  }

  /// Executes Supplier Stock Availability (OOS) scanning.
  Future<ExtractedSupplierStockData> extractSupplierStock({
    required List<Uint8List> images,
    List<InventoryItem>? catalog,
    List<InventoryItem>? dealerCatalog,
    required String scanMode,
    List<String> providerOrder = const ['gemini', 'groq'],
    AiScanTimingTracker? tracker,
  }) async {
    final effectiveCatalog = catalog ?? dealerCatalog ?? [];
    final swOcr = Stopwatch()..start();
    final ocrResult = await ocrEngine.recognizeMultipleBytes(images);
    swOcr.stop();

    final swParse = Stopwatch()..start();
    final parsedDoc = SupplierStockParser.parse(ocrResult);
    swParse.stop();

    final swMatch = Stopwatch()..start();
    final mappings = await _fetchMappings();

    final matcher = CatalogMatcher(
      catalog: effectiveCatalog,
      learnedMappings: mappings,
    );

    final rowMatches = <RowMatchResult>[];
    for (final row in parsedDoc.rows) {
      rowMatches.add(
        matcher.matchRow(
          row,
          isPurchaseOrder: true,
          sourceFilter: InventoryProductSource.selecta,
        ),
      );
    }
    swMatch.stop();

    tracker?.recordPipelineTiming(
      ocrMs: swOcr.elapsedMilliseconds,
      parseMs: swParse.elapsedMilliseconds,
      matchMs: swMatch.elapsedMilliseconds,
      llmMs: 0,
      unresolvedCount: rowMatches.where((m) => !m.isResolved).length,
      providerUsed: 'none (local)',
    );

    return matcher.mapToSupplierStockData(parsedDoc, rowMatches);
  }

  /// Compares official invoice against original PO items.
  Future<InvoiceComparisonResult> compareInvoiceWithPo({
    required List<Uint8List> images,
    List<InventoryItem>? catalog,
    required List<OrderItem> originalPoItems,
    String originalPoNumber = '',
    required String scanMode,
    List<String> providerOrder = const ['gemini', 'groq'],
    AiScanTimingTracker? tracker,
  }) async {
    final effectiveCatalog = catalog ??
        originalPoItems
            .map((item) => InventoryItem(
                  id: item.productId,
                  productName: item.productName,
                  imageUrl: '',
                  itemCode: '',
                  buyingPrice: item.buyingPrice,
                  sellingPrice: item.sellingPrice,
                  isActive: true,
                  stockQuantity: item.orderedQuantity,
                  lowStockThreshold: 0,
                  source: InventoryProductSource.selecta,
                ))
            .toList();

    final swOcr = Stopwatch()..start();
    final ocrResult = await ocrEngine.recognizeMultipleBytes(images);
    swOcr.stop();

    final swParse = Stopwatch()..start();
    final parsedDoc = PurchaseOrderParser.parse(ocrResult);
    swParse.stop();

    final swMatch = Stopwatch()..start();
    final mappings = await _fetchMappings();

    final matcher = CatalogMatcher(
      catalog: effectiveCatalog,
      learnedMappings: mappings,
    );

    final rowMatches = <RowMatchResult>[];
    for (final row in parsedDoc.rows) {
      rowMatches.add(matcher.matchRow(row, isPurchaseOrder: true));
    }
    swMatch.stop();

    final unresolvedMatches = rowMatches.where((m) => !m.isResolved).toList();
    String rawLlmResponse = '';
    final swLlm = Stopwatch()..start();

    if (scanMode == 'hybrid' && unresolvedMatches.isNotEmpty) {
      try {
        final llmResult = await _resolveWithTextLlm(
          unresolvedMatches: unresolvedMatches,
          parsedDoc: parsedDoc,
          catalog: effectiveCatalog,
          providerOrder: providerOrder,
        );
        rawLlmResponse = llmResult.rawResponse;

        _applyLlmResolutions(
          rowMatches: rowMatches,
          llmResolutions: llmResult.resolutions,
          catalog: effectiveCatalog,
        );
      } catch (e) {
        debugPrint('AiScanPipeline: Invoice comparison hybrid LLM step failed: $e');
      }
    }
    swLlm.stop();

    tracker?.recordPipelineTiming(
      ocrMs: swOcr.elapsedMilliseconds,
      parseMs: swParse.elapsedMilliseconds,
      matchMs: swMatch.elapsedMilliseconds,
      llmMs: swLlm.elapsedMilliseconds,
      unresolvedCount: unresolvedMatches.length,
      providerUsed: providerChain.lastUsedProviderId ?? 'none (local)',
    );

    return matcher.mapToInvoiceComparison(
      parsedDoc,
      rowMatches,
      originalPoItems,
      rawResponse: rawLlmResponse,
    );
  }

  /// Compact text prompt construction sending ONLY unresolved lines and candidates.
  Future<_LlmResolutionResult> _resolveWithTextLlm({
    required List<RowMatchResult> unresolvedMatches,
    required ParsedDocument parsedDoc,
    required List<InventoryItem> catalog,
    required List<String> providerOrder,
  }) async {
    final catalogById = {for (final item in catalog) item.id: item};
    final itemsList = <Map<String, dynamic>>[];

    for (int i = 0; i < unresolvedMatches.length; i++) {
      final match = unresolvedMatches[i];
      final candidates = match.topCandidates.take(5).map((c) => {
            'product_id': c.item.id,
            'name': c.item.productName,
            'price': c.item.buyingPrice,
          }).toList();

      itemsList.add({
        'row_index': i,
        'raw_text': match.row.rawText,
        'description': match.row.description,
        'unit_price': match.row.unitPrice,
        'quantity': match.row.quantity,
        'candidates': candidates,
      });
    }

    final promptData = {
      if (parsedDoc.invoiceNumber.isEmpty || parsedDoc.invoiceDate == null)
        'document_header_context': {
          'invoice_number_hint': parsedDoc.invoiceNumber,
          'invoice_date_hint': parsedDoc.invoiceDate != null
              ? DateFormat('yyyy-MM-dd').format(parsedDoc.invoiceDate!)
              : null,
          'total_amount_hint': parsedDoc.totalAmount,
        },
      'unresolved_rows': itemsList,
    };

    final prompt =
        'Given these unresolved OCR invoice lines and catalog candidates, resolve each row to the correct product_id (or null if not in catalog), '
        'and verify the delivered quantity.\n\n'
        'INPUT DATA:\n${jsonEncode(promptData)}\n\n'
        'Return JSON matching this format:\n'
        '{\n'
        '  "resolutions": [\n'
        '    {"row_index": 0, "product_id": "string or null", "quantity": 10, "confidence": 0.95}\n'
        '  ]\n'
        '}';

    final jsonStr = await providerChain.generateJson(
      prompt,
      schemaHint: '{"resolutions": [{"row_index": int, "product_id": string, "quantity": int, "confidence": double}]}',
      providerOrder: providerOrder,
    );

    final List<_LlmRowResolution> resolutions = [];
    try {
      final data = jsonDecode(jsonStr);
      final list = data['resolutions'] as List? ?? [];
      for (final item in list) {
        if (item is Map) {
          final rowIdx = (item['row_index'] as num?)?.toInt();
          final pid = item['product_id']?.toString();
          final qty = (item['quantity'] as num?)?.toInt();
          final conf = (item['confidence'] as num?)?.toDouble() ?? 0.90;

          // Hallucination Guard: Ensure product_id actually exists in catalog!
          if (rowIdx != null && pid != null && catalogById.containsKey(pid)) {
            resolutions.add(
              _LlmRowResolution(
                rowIndex: rowIdx,
                productId: pid,
                quantity: qty,
                confidence: conf,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('AiScanPipeline: Failed to decode LLM JSON resolution: $e');
    }

    return _LlmResolutionResult(resolutions: resolutions, rawResponse: jsonStr);
  }

  void _applyLlmResolutions({
    required List<RowMatchResult> rowMatches,
    required List<_LlmRowResolution> llmResolutions,
    required List<InventoryItem> catalog,
  }) {
    final catalogById = {for (final item in catalog) item.id: item};
    final unresolved = rowMatches.where((m) => !m.isResolved).toList();

    for (final res in llmResolutions) {
      if (res.rowIndex >= 0 && res.rowIndex < unresolved.length) {
        final targetMatch = unresolved[res.rowIndex];
        final matchedItem = catalogById[res.productId];
        if (matchedItem != null && res.confidence >= 0.70) {
          final matchIdx = rowMatches.indexOf(targetMatch);
          if (matchIdx != -1) {
            rowMatches[matchIdx] = RowMatchResult(
              row: ParsedRow(
                lines: targetMatch.row.lines,
                rawText: targetMatch.row.rawText,
                itemCode: targetMatch.row.itemCode,
                description: targetMatch.row.description,
                quantity: res.quantity ?? targetMatch.row.quantity,
                unitPrice: targetMatch.row.unitPrice,
                lineAmount: targetMatch.row.lineAmount,
                uom: targetMatch.row.uom,
                needsReview: false,
                confidence: res.confidence,
                pageIndex: targetMatch.row.pageIndex,
                y: targetMatch.row.y,
              ),
              status: MatchStatus.matched,
              matchedItem: matchedItem,
              confidence: res.confidence,
              reason: 'Resolved by ${providerChain.lastUsedProviderId ?? "AI"} (${(res.confidence * 100).toStringAsFixed(0)}%)',
            );
          }
        }
      }
    }
  }
}

class _LlmRowResolution {
  final int rowIndex;
  final String productId;
  final int? quantity;
  final double confidence;

  const _LlmRowResolution({
    required this.rowIndex,
    required this.productId,
    this.quantity,
    required this.confidence,
  });
}

class _LlmResolutionResult {
  final List<_LlmRowResolution> resolutions;
  final String rawResponse;

  const _LlmResolutionResult({
    required this.resolutions,
    required this.rawResponse,
  });
}
