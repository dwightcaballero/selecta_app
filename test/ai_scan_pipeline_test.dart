import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/ai/ai_provider_chain.dart';
import 'package:selecta_ops/services/ai/text_llm_provider.dart';
import 'package:selecta_ops/services/ai_scan_pipeline.dart';
import 'package:selecta_ops/services/ocr/ocr_engine.dart';
import 'package:selecta_ops/services/ocr/ocr_result.dart';

class MockOcrEngine implements OcrEngine {
  final OcrResult Function(Uint8List bytes) onRecognize;

  MockOcrEngine(this.onRecognize);

  @override
  bool get isSupported => true;

  @override
  Future<OcrResult> recognizeBytes(Uint8List imageBytes, {int pageIndex = 0}) async {
    return onRecognize(imageBytes);
  }

  @override
  Future<OcrResult> recognizeMultipleBytes(List<Uint8List> imageBytesList) async {
    if (imageBytesList.isEmpty) return const OcrResult();
    return onRecognize(imageBytesList.first);
  }

  @override
  Future<void> dispose() async {}
}

class MockTextLlmProvider implements TextLlmProvider {
  @override
  final String id = 'gemini';

  @override
  final String displayName = 'Mock Gemini Provider';

  @override
  bool get isConfigured => true;

  int callCount = 0;
  String? lastPrompt;
  String responseToReturn;

  MockTextLlmProvider({this.responseToReturn = '{}'});

  @override
  Future<String> generateJson(
    String prompt, {
    String? schemaHint,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    callCount++;
    lastPrompt = prompt;
    return responseToReturn;
  }

  @override
  Future<String> chat(
    List<Map<String, String>> messages, {
    String? systemPrompt,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    callCount++;
    lastPrompt = messages.isNotEmpty ? messages.last['content'] : '';
    return responseToReturn;
  }
}

void main() {
  group('AiScanPipeline Integration Tests', () {
    final catalog = [
      const InventoryItem(
        id: 'item-corn-choc',
        productName: 'Cornetto Classic Chocolate',
        imageUrl: '',
        itemCode: '10423',
        buyingPrice: 240.0,
        sellingPrice: 300.0,
        isActive: true,
        stockQuantity: 100,
        lowStockThreshold: 10,
        source: InventoryProductSource.selecta,
      ),
      const InventoryItem(
        id: 'item-mag-almond',
        productName: 'Magnum Almond Bar',
        imageUrl: '',
        itemCode: '20101',
        buyingPrice: 180.0,
        sellingPrice: 240.0,
        isActive: true,
        stockQuantity: 50,
        lowStockThreshold: 10,
        source: InventoryProductSource.selecta,
      ),
    ];

    test('Purchase Order in ocr_local mode: 100% on-device match with 0 LLM calls', () async {
      final mockOcr = MockOcrEngine((bytes) {
        return OcrResult(
          pages: [
            OcrPage(
              pageIndex: 0,
              width: 1000,
              height: 2000,
              blocks: [
                OcrBlock(
                  text: 'INVOICE NO: INV-2026-999\nDATE: 10/28/2026\nTOTAL: PHP 4,200.00',
                  boundingBox: const Rect.fromLTWH(50, 50, 800, 100),
                  lines: [
                    OcrLine(
                      text: 'INVOICE NO: INV-2026-999',
                      boundingBox: const Rect.fromLTWH(50, 50, 320, 20),
                      elements: [
                        OcrElement(text: 'INVOICE', boundingBox: const Rect.fromLTWH(50, 50, 100, 20)),
                        OcrElement(text: 'NO:', boundingBox: const Rect.fromLTWH(160, 50, 50, 20)),
                        OcrElement(text: 'INV-2026-999', boundingBox: const Rect.fromLTWH(220, 50, 150, 20)),
                      ],
                    ),
                    OcrLine(
                      text: 'DATE: 10/28/2026',
                      boundingBox: const Rect.fromLTWH(50, 80, 210, 20),
                      elements: [
                        OcrElement(text: 'DATE:', boundingBox: const Rect.fromLTWH(50, 80, 80, 20)),
                        OcrElement(text: '10/28/2026', boundingBox: const Rect.fromLTWH(140, 80, 120, 20)),
                      ],
                    ),
                    OcrLine(
                      text: 'TOTAL: PHP 4,200.00',
                      boundingBox: const Rect.fromLTWH(50, 110, 250, 20),
                      elements: [
                        OcrElement(text: 'TOTAL:', boundingBox: const Rect.fromLTWH(50, 110, 80, 20)),
                        OcrElement(text: 'PHP', boundingBox: const Rect.fromLTWH(140, 110, 50, 20)),
                        OcrElement(text: '4,200.00', boundingBox: const Rect.fromLTWH(200, 110, 100, 20)),
                      ],
                    ),
                  ],
                ),
                OcrBlock(
                  text: '10423 CRNTTO CLASIC CHOC 10 240.00 2400.00\n20101 MGNM ALMND 10 180.00 1800.00',
                  boundingBox: const Rect.fromLTWH(50, 300, 800, 100),
                  lines: [
                    OcrLine(
                      text: '10423 CRNTTO CLASIC CHOC 10 240.00 2400.00',
                      boundingBox: const Rect.fromLTWH(50, 300, 690, 20),
                      elements: [
                        OcrElement(text: '10423', boundingBox: const Rect.fromLTWH(50, 300, 80, 20)),
                        OcrElement(text: 'CRNTTO CLASIC CHOC', boundingBox: const Rect.fromLTWH(150, 300, 200, 20)),
                        OcrElement(text: '10', boundingBox: const Rect.fromLTWH(400, 300, 40, 20)),
                        OcrElement(text: '240.00', boundingBox: const Rect.fromLTWH(500, 300, 80, 20)),
                        OcrElement(text: '2400.00', boundingBox: const Rect.fromLTWH(650, 300, 90, 20)),
                      ],
                    ),
                    OcrLine(
                      text: '20101 MGNM ALMND 10 180.00 1800.00',
                      boundingBox: const Rect.fromLTWH(50, 350, 690, 20),
                      elements: [
                        OcrElement(text: '20101', boundingBox: const Rect.fromLTWH(50, 350, 80, 20)),
                        OcrElement(text: 'MGNM ALMND', boundingBox: const Rect.fromLTWH(150, 350, 150, 20)),
                        OcrElement(text: '10', boundingBox: const Rect.fromLTWH(400, 350, 40, 20)),
                        OcrElement(text: '180.00', boundingBox: const Rect.fromLTWH(500, 350, 80, 20)),
                        OcrElement(text: '1800.00', boundingBox: const Rect.fromLTWH(650, 350, 90, 20)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      });

      final mockLlm = MockTextLlmProvider();
      final chain = AiProviderChain(providers: [mockLlm]);
      final pipeline = AiScanPipeline(ocrEngine: mockOcr, providerChain: chain);

      final result = await pipeline.extractPurchaseOrder(
        images: [Uint8List(10)],
        catalog: catalog,
        scanMode: 'ocr_local',
      );

      expect(mockLlm.callCount, 0, reason: 'ocr_local mode must not trigger LLM calls');
      expect(result.invoiceNumber, 'INV-2026-999');
      expect(result.invoiceDate, DateTime(2026, 10, 28));
      expect(result.totalAmount, 4200.0);
      expect(result.matchedItems.length, 2);
      expect(result.matchedItems[0].productId, 'item-corn-choc');
      expect(result.matchedItems[0].quantity, 10);
      expect(result.matchedItems[1].productId, 'item-mag-almond');
      expect(result.matchedItems[1].quantity, 10);
    });

    test('Purchase Order in hybrid mode: resolves ambiguous lines via compact LLM fallback', () async {
      final mockOcr = MockOcrEngine((bytes) {
        return OcrResult(
          pages: [
            OcrPage(
              pageIndex: 0,
              width: 1000,
              height: 2000,
              blocks: [
                OcrBlock(
                  text: 'UNKNOWN ICE CREAM TXT 5 180.00',
                  boundingBox: const Rect.fromLTWH(50, 300, 500, 30),
                  lines: [
                    OcrLine(
                      text: 'UNKNOWN ICE CREAM TXT 5 180.00',
                      boundingBox: const Rect.fromLTWH(50, 300, 440, 20),
                      elements: [
                        OcrElement(text: 'UNKNOWN', boundingBox: const Rect.fromLTWH(50, 300, 100, 20)),
                        OcrElement(text: 'ICE CREAM TXT', boundingBox: const Rect.fromLTWH(160, 300, 150, 20)),
                        OcrElement(text: '5', boundingBox: const Rect.fromLTWH(350, 300, 30, 20)),
                        OcrElement(text: '180.00', boundingBox: const Rect.fromLTWH(420, 300, 70, 20)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      });

      final mockLlm = MockTextLlmProvider(
        responseToReturn: '''
{
  "resolutions": [
    {
      "row_index": 0,
      "product_id": "item-mag-almond",
      "quantity": 5,
      "confidence": 0.95
    }
  ]
}
''',
      );
      final chain = AiProviderChain(providers: [mockLlm]);
      final pipeline = AiScanPipeline(ocrEngine: mockOcr, providerChain: chain);

      final result = await pipeline.extractPurchaseOrder(
        images: [Uint8List(10)],
        catalog: catalog,
        scanMode: 'hybrid',
      );

      expect(mockLlm.callCount, 1, reason: 'Hybrid mode should query LLM for unresolved lines');
      expect(result.matchedItems.length, 1);
      expect(result.matchedItems.first.productId, 'item-mag-almond');
      expect(result.matchedItems.first.quantity, 5);
    });

    test('Hallucination guard: discards invalid product IDs returned by LLM', () async {
      final mockOcr = MockOcrEngine((bytes) {
        return OcrResult(
          pages: [
            OcrPage(
              pageIndex: 0,
              width: 1000,
              height: 2000,
              blocks: [
                OcrBlock(
                  text: 'RANDOM BRAND WAFER 3',
                  boundingBox: const Rect.fromLTWH(50, 300, 400, 30),
                  lines: [
                    OcrLine(
                      text: 'RANDOM BRAND WAFER 3',
                      boundingBox: const Rect.fromLTWH(50, 300, 330, 20),
                      elements: [
                        OcrElement(text: 'RANDOM', boundingBox: const Rect.fromLTWH(50, 300, 100, 20)),
                        OcrElement(text: 'BRAND WAFER', boundingBox: const Rect.fromLTWH(160, 300, 150, 20)),
                        OcrElement(text: '3', boundingBox: const Rect.fromLTWH(350, 300, 30, 20)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      });

      final mockLlm = MockTextLlmProvider(
        responseToReturn: '''
{
  "resolutions": [
    {
      "row_index": 0,
      "product_id": "hallucinated-id-9999",
      "quantity": 3,
      "confidence": 0.95
    }
  ]
}
''',
      );
      final chain = AiProviderChain(providers: [mockLlm]);
      final pipeline = AiScanPipeline(ocrEngine: mockOcr, providerChain: chain);

      final result = await pipeline.extractPurchaseOrder(
        images: [Uint8List(10)],
        catalog: catalog,
        scanMode: 'hybrid',
      );

      expect(mockLlm.callCount, 1);
      expect(result.matchedItems.isEmpty, true, reason: 'Hallucinated item IDs not in catalog must be rejected');
      expect(result.unmatchedItems.isNotEmpty, true);
    });

    test('Invoice comparison against original PO items in ocr_local mode', () async {
      final mockOcr = MockOcrEngine((bytes) {
        return OcrResult(
          pages: [
            OcrPage(
              pageIndex: 0,
              width: 1000,
              height: 2000,
              blocks: [
                OcrBlock(
                  text: 'INV-101\nCORNETTO CLASSIC CHOC 8 240.00 1920.00',
                  boundingBox: const Rect.fromLTWH(50, 50, 600, 300),
                  lines: [
                    OcrLine(
                      text: 'INV-101',
                      boundingBox: const Rect.fromLTWH(50, 50, 100, 20),
                      elements: [
                        OcrElement(text: 'INV-101', boundingBox: const Rect.fromLTWH(50, 50, 100, 20)),
                      ],
                    ),
                    OcrLine(
                      text: 'CORNETTO CLASSIC CHOC 8 240.00 1920.00',
                      boundingBox: const Rect.fromLTWH(50, 300, 530, 20),
                      elements: [
                        OcrElement(text: 'CORNETTO CLASSIC CHOC', boundingBox: const Rect.fromLTWH(50, 300, 200, 20)),
                        OcrElement(text: '8', boundingBox: const Rect.fromLTWH(300, 300, 30, 20)),
                        OcrElement(text: '240.00', boundingBox: const Rect.fromLTWH(400, 300, 70, 20)),
                        OcrElement(text: '1920.00', boundingBox: const Rect.fromLTWH(500, 300, 80, 20)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      });

      final chain = AiProviderChain();
      final pipeline = AiScanPipeline(ocrEngine: mockOcr, providerChain: chain);

      final poItems = [
        OrderItem(
          productId: 'item-corn-choc',
          productName: 'Cornetto Classic Chocolate',
          orderedQuantity: 10,
          buyingPrice: 240.0,
          sellingPrice: 300.0,
        ),
        OrderItem(
          productId: 'item-mag-almond',
          productName: 'Magnum Almond Bar',
          orderedQuantity: 5,
          buyingPrice: 180.0,
          sellingPrice: 240.0,
        ),
      ];

      final result = await pipeline.compareInvoiceWithPo(
        images: [Uint8List(10)],
        originalPoItems: poItems,
        originalPoNumber: 'PO-2026-001',
        scanMode: 'ocr_local',
      );

      expect(result.invoiceNumber, '101');
      expect(result.confirmedItems.length, 1);
      expect(result.confirmedItems.first.productId, 'item-corn-choc');
      expect(result.confirmedItems.first.deliveredQuantity, 8);
      expect(result.confirmedItems.first.orderedQuantity, 10);

      expect(result.missingItems.length, 1);
      expect(result.missingItems.first.productId, 'item-mag-almond');
    });

    test('Supplier Stock Status extraction in ocr_local mode', () async {
      final mockOcr = MockOcrEngine((bytes) {
        return OcrResult(
          pages: [
            OcrPage(
              pageIndex: 0,
              width: 1000,
              height: 2000,
              blocks: [
                OcrBlock(
                  text: 'MAGNUM ALMOND OOS\nCORNETTO CLASSIC CHOC AVAILABLE 50',
                  boundingBox: const Rect.fromLTWH(50, 200, 400, 100),
                  lines: [
                    OcrLine(
                      text: 'MAGNUM ALMOND OOS',
                      boundingBox: const Rect.fromLTWH(50, 200, 250, 20),
                      elements: [
                        OcrElement(text: 'MAGNUM ALMOND', boundingBox: const Rect.fromLTWH(50, 200, 150, 20)),
                        OcrElement(text: 'OOS', boundingBox: const Rect.fromLTWH(250, 200, 50, 20)),
                      ],
                    ),
                    OcrLine(
                      text: 'CORNETTO CLASSIC CHOC AVAILABLE 50',
                      boundingBox: const Rect.fromLTWH(50, 250, 370, 20),
                      elements: [
                        OcrElement(text: 'CORNETTO CLASSIC CHOC', boundingBox: const Rect.fromLTWH(50, 250, 200, 20)),
                        OcrElement(text: 'AVAILABLE', boundingBox: const Rect.fromLTWH(280, 250, 80, 20)),
                        OcrElement(text: '50', boundingBox: const Rect.fromLTWH(380, 250, 40, 20)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      });

      final chain = AiProviderChain();
      final pipeline = AiScanPipeline(ocrEngine: mockOcr, providerChain: chain);

      final result = await pipeline.extractSupplierStock(
        images: [Uint8List(10)],
        dealerCatalog: catalog,
        scanMode: 'ocr_local',
      );

      expect(result.isProductOutOfStock('item-mag-almond'), true);
      expect(result.isProductOutOfStock('item-corn-choc'), false);
      expect(result.matchedItems.length, 2);
      final cornetto = result.matchedItems.firstWhere((i) => i.productId == 'item-corn-choc');
      expect(cornetto.supplierAvailableQuantity, 50);
    });
  });
}
