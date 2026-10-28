import 'dart:math';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/ocr/document_layout_parser.dart';
import 'package:selecta_ops/services/ocr/text_normalizer.dart';

/// Single candidate product matched against an OCR document row.
class MatchCandidate {
  final InventoryItem item;
  final double score;
  final String reason;

  const MatchCandidate({
    required this.item,
    required this.score,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'productId': item.id,
        'productName': item.productName,
        'score': score,
        'reason': reason,
      };
}

/// Status classification of an OCR row match against the product catalog.
enum MatchStatus {
  matched,
  ambiguous,
  unmatched,
}

/// Output result of matching a single [ParsedRow] against the catalog and learned mappings.
class RowMatchResult {
  final ParsedRow row;
  final MatchStatus status;
  final InventoryItem? matchedItem;
  final List<MatchCandidate> topCandidates;
  final double confidence;
  final String reason;

  const RowMatchResult({
    required this.row,
    required this.status,
    this.matchedItem,
    this.topCandidates = const [],
    this.confidence = 1.0,
    this.reason = '',
  });

  bool get isResolved => status == MatchStatus.matched && matchedItem != null;
}

/// High-speed local catalog matching engine with alias exact matching,
/// inverted token index, Jaccard/Jaro-Winkler fuzzy scoring, and price tie-breaking.
class CatalogMatcher {
  final List<InventoryItem> catalog;
  final List<SupplierProductMapping> learnedMappings;
  final Map<String, InventoryItem> _catalogById;
  final Map<String, InventoryItem> _catalogByItemCode;
  final Map<String, List<InventoryItem>> _tokenInvertedIndex = {};

  CatalogMatcher({
    required this.catalog,
    this.learnedMappings = const [],
  })  : _catalogById = {for (final item in catalog) item.id: item},
        _catalogByItemCode = {
          for (final item in catalog)
            if (item.itemCode.trim().isNotEmpty) item.itemCode.trim(): item
        } {
    _buildTokenIndex();
  }

  void _buildTokenIndex() {
    for (final item in catalog) {
      final normName = TextNormalizer.normalizeAndExpand(item.productName);
      final tokens = normName.split(' ').where((w) => w.length > 1).toSet();
      for (final t in tokens) {
        _tokenInvertedIndex.putIfAbsent(t, () => []).add(item);
      }
    }
  }

  /// Matches a single [ParsedRow] against the catalog.
  RowMatchResult matchRow(
    ParsedRow row, {
    bool isPurchaseOrder = true,
    InventoryProductSource? sourceFilter,
  }) {
    final normRaw = TextNormalizer.normalize(row.description.isNotEmpty ? row.description : row.rawText);

    // -------------------------------------------------------------
    // Step 1: Learned alias match from SupplierProductMapping
    // -------------------------------------------------------------
    if (learnedMappings.isNotEmpty && normRaw.isNotEmpty) {
      for (final mapping in learnedMappings) {
        final normMapping = TextNormalizer.normalize(mapping.rawSupplierText);
        final isExact = normRaw == normMapping || normRaw == TextNormalizer.normalize(mapping.normalizedText);
        final isPrefix = (normRaw.length >= 6 && normMapping.startsWith(normRaw)) ||
            (normMapping.length >= 6 && normRaw.startsWith(normMapping));

        if (isExact || isPrefix) {
          if (mapping.isMultiMatch || mapping.candidateProductIds.length > 1) {
            final candidates = mapping.candidateProductIds
                .map((id) => _catalogById[id])
                .whereType<InventoryItem>()
                .map((item) => MatchCandidate(item: item, score: 0.85, reason: 'multi_alias_learned'))
                .toList();

            if (candidates.isNotEmpty) {
              return RowMatchResult(
                row: row,
                status: MatchStatus.ambiguous,
                topCandidates: candidates,
                confidence: 0.85,
                reason: 'Learned multi-product alias from previous user confirmation.',
              );
            }
          }

          final targetItem = _catalogById[mapping.productId];
          if (targetItem != null && (sourceFilter == null || targetItem.source == sourceFilter)) {
            return RowMatchResult(
              row: row,
              status: MatchStatus.matched,
              matchedItem: targetItem,
              confidence: 0.99,
              reason: 'Learned alias confirmed by user.',
            );
          }
        }
      }
    }

    // -------------------------------------------------------------
    // Step 2: Item code exact match
    // -------------------------------------------------------------
    if (row.itemCode != null && row.itemCode!.isNotEmpty) {
      final itemByCode = _catalogByItemCode[row.itemCode!.trim()];
      if (itemByCode != null && (sourceFilter == null || itemByCode.source == sourceFilter)) {
        return RowMatchResult(
          row: row,
          status: MatchStatus.matched,
          matchedItem: itemByCode,
          confidence: 0.98,
          reason: 'Exact item code match (${row.itemCode}).',
        );
      }
    }

    // -------------------------------------------------------------
    // Step 3: Inverted token index candidate retrieval
    // -------------------------------------------------------------
    final queryExpanded = TextNormalizer.normalizeAndExpand(row.description.isNotEmpty ? row.description : row.rawText);
    final queryTokens = queryExpanded.split(' ').where((w) => w.length > 1).toSet();

    Set<InventoryItem> candidatePool = {};
    for (final t in queryTokens) {
      final matches = _tokenInvertedIndex[t];
      if (matches != null) {
        candidatePool.addAll(matches);
      }
    }

    if (candidatePool.isEmpty) {
      // Fall back to entire catalog if no tokens overlapped
      candidatePool = catalog.toSet();
    }

    // -------------------------------------------------------------
    // Step 4: Fuzzy scoring with price tie-breaking
    // -------------------------------------------------------------
    final scoredCandidates = <MatchCandidate>[];

    for (final item in candidatePool) {
      if (sourceFilter != null && item.source != sourceFilter) continue;

      double score = TextNormalizer.combinedSimilarity(queryExpanded, item.productName);

      // Price verification & tie-breaking:
      // compare detected unit price vs catalog buyingPrice (PO) or sellingPrice (Store)
      if (row.unitPrice > 0) {
        final catalogPrice = isPurchaseOrder ? item.buyingPrice : item.sellingPrice;
        if (catalogPrice > 0) {
          final priceDiffRatio = (catalogPrice - row.unitPrice).abs() / max(catalogPrice, 1.0);
          if (priceDiffRatio <= 0.10) {
            score += 0.10; // Strong price match bonus
          } else if (priceDiffRatio > 0.35) {
            score -= 0.25; // Size difference penalty (e.g. Pint vs Tub)
          }
        }
      }

      final boundedScore = score.clamp(0.0, 1.0);
      if (boundedScore >= 0.45) {
        scoredCandidates.add(
          MatchCandidate(
            item: item,
            score: boundedScore,
            reason: 'fuzzy_score: ${boundedScore.toStringAsFixed(2)}',
          ),
        );
      }
    }

    scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

    if (scoredCandidates.isEmpty) {
      return RowMatchResult(
        row: row,
        status: MatchStatus.unmatched,
        confidence: 0.0,
        reason: 'No catalog candidates found.',
      );
    }

    final top = scoredCandidates.first;

    // Check if second candidate is extremely close in score
    if (top.score >= 0.90) {
      if (scoredCandidates.length > 1) {
        final second = scoredCandidates[1];
        if ((top.score - second.score).abs() < 0.04) {
          // Ambiguous tie between close variants
          return RowMatchResult(
            row: row,
            status: MatchStatus.ambiguous,
            topCandidates: scoredCandidates.take(5).toList(),
            confidence: top.score,
            reason: 'Close score tie between top candidates.',
          );
        }
      }

      return RowMatchResult(
        row: row,
        status: MatchStatus.matched,
        matchedItem: top.item,
        confidence: top.score,
        reason: 'Confident catalog match (${(top.score * 100).toStringAsFixed(0)}%).',
      );
    }

    if (top.score >= 0.60) {
      return RowMatchResult(
        row: row,
        status: MatchStatus.ambiguous,
        topCandidates: scoredCandidates.take(5).toList(),
        confidence: top.score,
        reason: 'Plausible candidates found (${(top.score * 100).toStringAsFixed(0)}%). Disambiguation needed.',
      );
    }

    return RowMatchResult(
      row: row,
      status: MatchStatus.unmatched,
      topCandidates: scoredCandidates.take(3).toList(),
      confidence: top.score,
      reason: 'Low confidence match (${(top.score * 100).toStringAsFixed(0)}%).',
    );
  }

  /// Maps parsed document rows and match results into [ExtractedPurchaseOrderData].
  ExtractedPurchaseOrderData mapToPurchaseOrderData(
    ParsedDocument doc,
    List<RowMatchResult> matches, {
    String rawResponse = '',
  }) {
    final matchedItems = <ExtractedPoItem>[];
    final ambiguousItems = <AmbiguousPoItem>[];
    final unmatchedItems = <String>[];

    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.status == MatchStatus.matched && m.matchedItem != null) {
        matchedItems.add(
          ExtractedPoItem(
            productId: m.matchedItem!.id,
            matchedProductName: m.matchedItem!.productName,
            rawText: m.row.rawText,
            quantity: m.row.quantity,
            confidence: m.confidence,
          ),
        );
      } else if (m.status == MatchStatus.ambiguous) {
        ambiguousItems.add(
          AmbiguousPoItem(
            rawText: m.row.rawText,
            quantity: m.row.quantity,
            detectedUnitPrice: m.row.unitPrice,
            candidateProductIds: m.topCandidates.map((c) => c.item.id).toList(),
            reason: m.reason,
            documentIndex: m.row.pageIndex,
          ),
        );
      } else {
        unmatchedItems.add(m.row.rawText);
      }
    }

    return ExtractedPurchaseOrderData(
      invoiceNumber: doc.invoiceNumber,
      invoiceDate: doc.invoiceDate,
      totalAmount: doc.totalAmount,
      matchedItems: matchedItems,
      ambiguousItems: ambiguousItems,
      unmatchedItems: unmatchedItems,
      rawAiResponse: rawResponse,
    );
  }

  /// Maps parsed document rows and match results into [ExtractedSupplierStockData].
  ExtractedSupplierStockData mapToSupplierStockData(
    ParsedDocument doc,
    List<RowMatchResult> matches, {
    String rawResponse = '',
  }) {
    final matchedList = <SupplierStockItemStatus>[];
    final oosIds = <String>[];
    final inStockIds = <String>[];

    for (final m in matches) {
      if (m.matchedItem != null) {
        final pid = m.matchedItem!.id;
        final isOos = m.row.isOutOfStock;

        matchedList.add(
          SupplierStockItemStatus(
            productId: pid,
            matchedProductName: m.matchedItem!.productName,
            rawText: m.row.rawText,
            isOutOfStock: isOos,
            supplierAvailableQuantity: m.row.availableQuantity,
          ),
        );

        if (isOos) {
          oosIds.add(pid);
        } else {
          inStockIds.add(pid);
        }
      }
    }

    return ExtractedSupplierStockData(
      reportDate: doc.invoiceDate ?? DateTime.now(),
      matchedItems: matchedList,
      outOfStockProductIds: oosIds,
      inStockProductIds: inStockIds,
      rawAiResponse: rawResponse,
    );
  }

  /// Compares official invoice items against original PO items.
  InvoiceComparisonResult mapToInvoiceComparison(
    ParsedDocument doc,
    List<RowMatchResult> matches,
    List<OrderItem> originalPoItems, {
    String rawResponse = '',
  }) {
    final confirmed = <ConfirmedInvoiceItem>[];
    final confirmedProductIds = <String>{};

    for (final m in matches) {
      if (m.matchedItem != null) {
        final pid = m.matchedItem!.id;
        confirmedProductIds.add(pid);

        // Find matching item in original PO if available
        final orig = originalPoItems.where((p) => p.productId == pid).firstOrNull;

        confirmed.add(
          ConfirmedInvoiceItem(
            productId: pid,
            productName: m.matchedItem!.productName,
            imageUrl: m.matchedItem!.imageUrl,
            productSource: m.matchedItem!.source.key,
            category: m.matchedItem!.category,
            tag: m.matchedItem!.tag,
            unitCost: m.row.unitPrice > 0 ? m.row.unitPrice : m.matchedItem!.buyingPrice,
            sellingPrice: m.matchedItem!.sellingPrice,
            orderedQuantity: orig?.orderedQuantity ?? m.row.quantity,
            deliveredQuantity: m.row.quantity,
          ),
        );
      }
    }

    final missing = originalPoItems
        .where((p) => !confirmedProductIds.contains(p.productId))
        .toList();

    return InvoiceComparisonResult(
      invoiceNumber: doc.invoiceNumber,
      invoiceDate: doc.invoiceDate,
      totalAmount: doc.totalAmount,
      confirmedItems: confirmed,
      missingItems: missing,
      rawAiResponse: rawResponse,
    );
  }
}
