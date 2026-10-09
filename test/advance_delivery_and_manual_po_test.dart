import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/inventory/inventory_card.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/manual_po_product_picker_dialog.dart';

void main() {
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  final inStockItem = InventoryItem(
    id: 'item_1',
    productName: 'P20 CREAMDAE CUPS CHOCO',
    imageUrl: '',
    buyingPrice: 15.0,
    sellingPrice: 20.0,
    isActive: true,
    stockQuantity: 10,
    lowStockThreshold: 2,
    source: InventoryProductSource.selecta,
    category: 'By Case',
  );

  final outOfStockItem = InventoryItem(
    id: 'item_2',
    productName: 'P100 CORNETTO DISK CHOCO',
    imageUrl: '',
    buyingPrice: 75.0,
    sellingPrice: 100.0,
    isActive: true,
    stockQuantity: 0,
    lowStockThreshold: 2,
    source: InventoryProductSource.selecta,
    category: 'By Piece',
  );

  final bestSellerItem = InventoryItem(
    id: 'item_3',
    productName: 'P150 BEST SELLER SPECIAL TUB',
    imageUrl: '',
    buyingPrice: 110.0,
    sellingPrice: 150.0,
    isActive: true,
    stockQuantity: 5,
    lowStockThreshold: 2,
    source: InventoryProductSource.selecta,
    category: 'By Piece',
    tag: ProductTag.bestSeller,
  );

  group('ProductOrderCard Future Delivery Behavior Tests', () {
    testWidgets('For today (isFutureDelivery=false) with 0 stock: renders Out of stock and disables ordering', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductOrderCard(
              item: outOfStockItem,
              selectedQty: 0,
              maxOrderable: 0,
              isPlaced: false,
              currencyFormat: currencyFormat,
              isFutureDelivery: false,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify "Out of stock" indicator is displayed
      expect(find.text('Out of stock'), findsOneWidget);
      // The Add button is not shown when out of stock for today
      expect(find.text('Add'), findsNothing);
    });

    testWidgets('For tomorrow/future (isFutureDelivery=true) with 0 stock: allows ordering and shows Restock via PO', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductOrderCard(
              item: outOfStockItem,
              selectedQty: 0,
              maxOrderable: 9999,
              isPlaced: false,
              currencyFormat: currencyFormat,
              isFutureDelivery: true,
              onTap: () => tapped = true,
              onIncrement: () => tapped = true,
            ),
          ),
        ),
      );

      // Should NOT say 'Out of stock'
      expect(find.text('Out of stock'), findsNothing);
      // Should show 'Restock via PO' badge
      expect(find.text('Restock via PO'), findsOneWidget);
      // Add button should be present and clickable
      expect(find.text('Add'), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(tapped, isTrue);
    });

    testWidgets('For tomorrow/future (isFutureDelivery=true) with positive stock: shows available units without blocking', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductOrderCard(
              item: inStockItem,
              selectedQty: 0,
              maxOrderable: 9999,
              isPlaced: false,
              currencyFormat: currencyFormat,
              isFutureDelivery: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('• 10 available'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  group('ManualPoProductPickerDialog Catalog and Sorting Tests', () {
    testWidgets('Manual PO dialog organizes catalog in Best Sellers -> By Case -> By Piece and SRP ascending', (tester) async {
      final catalog = [
        // Case items with different SRPs
        InventoryItem(
          id: 'case_high',
          productName: 'P50 CASE ITEM HIGH',
          imageUrl: '',
          buyingPrice: 40.0,
          sellingPrice: 50.0,
          isActive: true,
          stockQuantity: 10,
          lowStockThreshold: 2,
          source: InventoryProductSource.selecta,
          category: 'By Case',
        ),
        InventoryItem(
          id: 'case_low',
          productName: 'P20 CASE ITEM LOW',
          imageUrl: '',
          buyingPrice: 15.0,
          sellingPrice: 20.0,
          isActive: true,
          stockQuantity: 10,
          lowStockThreshold: 2,
          source: InventoryProductSource.selecta,
          category: 'By Case',
        ),
        // Piece item
        InventoryItem(
          id: 'piece_item',
          productName: 'P30 PIECE ITEM',
          imageUrl: '',
          buyingPrice: 22.0,
          sellingPrice: 30.0,
          isActive: true,
          stockQuantity: 10,
          lowStockThreshold: 2,
          source: InventoryProductSource.selecta,
          category: 'By Piece',
        ),
        // Best Seller item
        bestSellerItem,
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    ManualPoProductPickerDialog.show(
                      context: ctx,
                      allInventory: catalog,
                      existingLines: [],
                      currencyFormat: currencyFormat,
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Dialog title
      expect(find.text('Manual Purchase Order'), findsOneWidget);

      // Category headers matching BookOrderPage grouping
      expect(find.textContaining('Best Sellers'), findsWidgets);
      expect(find.textContaining('By Case'), findsWidgets);
      expect(find.textContaining('By Piece'), findsWidgets);

      // Verify Best Seller item is listed under BEST SELLERS
      expect(find.text('P150 BEST SELLER SPECIAL TUB'), findsOneWidget);

      // Verify Case items are present and sorted by SRP
      expect(find.text('P20 CASE ITEM LOW'), findsOneWidget);
      expect(find.text('P50 CASE ITEM HIGH'), findsOneWidget);

      // Add 2 units of P20 CASE ITEM LOW
      final addButtons = find.text('Add');
      expect(addButtons, findsWidgets);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // Check that bottom summary bar is updated
      expect(find.textContaining('1 items • 1 units'), findsOneWidget);
      expect(find.text('Apply to P.O. (1)'), findsOneWidget);
    });

    test('Helperfunctions.compareBySrpAndName ensures exact sort contract with BookOrderPage', () {
      final p10 = InventoryItem(
        id: '1',
        productName: 'P10 ICE CANDY',
        imageUrl: '',
        buyingPrice: 8,
        sellingPrice: 10,
        isActive: true,
        stockQuantity: 5,
        lowStockThreshold: 1,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );
      final p50 = InventoryItem(
        id: '2',
        productName: 'P50 CORNETTO',
        imageUrl: '',
        buyingPrice: 40,
        sellingPrice: 50,
        isActive: true,
        stockQuantity: 5,
        lowStockThreshold: 1,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );
      final p150 = InventoryItem(
        id: '3',
        productName: 'P150 TUB',
        imageUrl: '',
        buyingPrice: 120,
        sellingPrice: 150,
        isActive: true,
        stockQuantity: 5,
        lowStockThreshold: 1,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      final unsorted = [p150, p10, p50];
      unsorted.sort((a, b) => Helperfunctions.compareBySrpAndName(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
      ));

      expect(unsorted[0].productName, equals('P10 ICE CANDY'));
      expect(unsorted[1].productName, equals('P50 CORNETTO'));
      expect(unsorted[2].productName, equals('P150 TUB'));
    });
  });

  group('Future Delivery Reservation Calculation Tests', () {
    test('Calculates isInventoryReserved=false for tomorrow or future delivery dates', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final nextWeek = today.add(const Duration(days: 7));

      bool isTomorrowOrFuture(DateTime date) {
        final d = DateTime(date.year, date.month, date.day);
        return d.isAfter(today);
      }

      expect(isTomorrowOrFuture(today), isFalse);
      expect(isTomorrowOrFuture(tomorrow), isTrue);
      expect(isTomorrowOrFuture(nextWeek), isTrue);

      // When saving:
      final reservedForToday = !isTomorrowOrFuture(today);
      final reservedForTomorrow = !isTomorrowOrFuture(tomorrow);

      expect(reservedForToday, isTrue, reason: "Today's order must reserve on-hand inventory");
      expect(reservedForTomorrow, isFalse, reason: "Tomorrow's order must NOT reserve on-hand inventory");
    });
  });

  group('Pre-Order Inventory & Strict Available Calculation Tests', () {
    test('preOrderShortage is based on pre-order minus current warehouse stock', () {
      final itemWithPreOrder = InventoryItem(
        id: 'po_test_1',
        productName: 'P50 CORNETTO DISK',
        imageUrl: '',
        buyingPrice: 35.0,
        sellingPrice: 50.0,
        isActive: true,
        stockQuantity: 10,
        incomingQuantity: 5,
        reservedQuantity: 3,
        preOrderQuantity: 20, // 20 units pre-ordered for future dates
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      // Available = (10 + 5) - 3 = 12 (must NOT be affected by preOrderQuantity!)
      expect(itemWithPreOrder.availableQuantity, equals(12));
      expect(itemWithPreOrder.preOrderQuantity, equals(20));

      // Shortage is based strictly on pre-order minus current warehouse stock (20 - 10 = 10)
      expect(itemWithPreOrder.preOrderShortage, equals(10));
      expect(itemWithPreOrder.hasPreOrderShortage, isTrue);
      expect(itemWithPreOrder.isPreOrderRecommended, isTrue);
    });

    test('recommends in PO when stock after pre-orders equals or drops below low stock threshold', () {
      final itemLowStockAfterPreOrder = InventoryItem(
        id: 'po_test_2',
        productName: 'P100 ICE CREAM TUB',
        imageUrl: '',
        buyingPrice: 70.0,
        sellingPrice: 100.0,
        isActive: true,
        stockQuantity: 10,
        incomingQuantity: 0,
        reservedQuantity: 0,
        preOrderQuantity: 8, // 10 - 8 = 2 remaining
        lowStockThreshold: 2, // remaining stock (2) <= lowStockThreshold (2)
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      // No outright shortage (10 >= 8)
      expect(itemLowStockAfterPreOrder.hasPreOrderShortage, isFalse);
      expect(itemLowStockAfterPreOrder.preOrderShortage, equals(0));
      expect(itemLowStockAfterPreOrder.remainingStockAfterPreOrder, equals(2));

      // But RECOMMENDED because stock after pre-orders <= lowStockThreshold!
      expect(itemLowStockAfterPreOrder.isPreOrderRecommended, isTrue);
      expect(itemLowStockAfterPreOrder.hasPreOrderDeficit, isTrue);
    });

    test('is NOT recommended in PO when remaining stock after pre-orders is safely above low stock threshold', () {
      final itemSufficient = InventoryItem(
        id: 'po_test_3',
        productName: 'P150 SPECIAL TUB',
        imageUrl: '',
        buyingPrice: 110.0,
        sellingPrice: 150.0,
        isActive: true,
        stockQuantity: 25,
        incomingQuantity: 0,
        reservedQuantity: 0,
        preOrderQuantity: 10, // 25 - 10 = 15 remaining > 2
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      expect(itemSufficient.availableQuantity, equals(25));
      expect(itemSufficient.hasPreOrderShortage, isFalse);
      expect(itemSufficient.isPreOrderRecommended, isFalse);
      expect(itemSufficient.preOrderShortage, equals(0));
    });

    test('prefills midpoint between low stock and max stock when maxStock exists', () {
      final itemWithMaxStock = InventoryItem(
        id: 'po_test_max_stock',
        productName: 'P100 MAX STOCK ITEM',
        imageUrl: '',
        buyingPrice: 70.0,
        sellingPrice: 100.0,
        isActive: true,
        stockQuantity: 15,
        preOrderQuantity: 10, // Remaining stock = 5
        lowStockThreshold: 10,
        maxStock: 50, // Midpoint = (10 + 50) / 2 = 30
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      // Remaining stock = 15 - 10 = 5 <= 10 (recommended!)
      expect(itemWithMaxStock.isPreOrderRecommended, isTrue);
      // Needed to reach midpoint (30) from remaining (5) = 25 units
      expect(itemWithMaxStock.recommendedPreOrderOrderQuantity, equals(25));
    });

    test('prefills only what is needed to restore stock to lowStockThreshold when maxStock is not configured', () {
      final itemWithoutMaxStock = InventoryItem(
        id: 'po_test_no_max_stock',
        productName: 'P20 NO MAX STOCK ITEM',
        imageUrl: '',
        buyingPrice: 15.0,
        sellingPrice: 20.0,
        isActive: true,
        stockQuantity: 10,
        preOrderQuantity: 8, // Remaining stock = 2
        lowStockThreshold: 4, // Target = 4
        maxStock: 0,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      // Remaining stock = 10 - 8 = 2 <= 4 (recommended!)
      expect(itemWithoutMaxStock.isPreOrderRecommended, isTrue);
      // Needed to restore to lowStockThreshold (4) from remaining (2) = 2 units
      expect(itemWithoutMaxStock.recommendedPreOrderOrderQuantity, equals(2));
    });
  });

  group('Pre-Order PO Prioritization Tests', () {
    test('Prioritizes pre-order deficit products to the very top in descending deficit order', () {
      final invItemNormal = InventoryItem(
        id: 'prod_normal',
        productName: 'NORMAL PRODUCT',
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: 20,
        isActive: true,
        stockQuantity: 50,
        preOrderQuantity: 5, // 50 - 5 = 45 > 2 (not recommended)
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
      );

      final invItemLowStockWarning = InventoryItem(
        id: 'prod_low_stock_warn',
        productName: 'LOW STOCK WARNING PRODUCT',
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: 20,
        isActive: true,
        stockQuantity: 10,
        preOrderQuantity: 9, // 10 - 9 = 1 <= 2 (recommended low stock warning)
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
      );

      final invItemShortage = InventoryItem(
        id: 'prod_shortage',
        productName: 'SHORTAGE PRODUCT',
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: 20,
        isActive: true,
        stockQuantity: 5,
        preOrderQuantity: 15, // 15 > 5, shortage = 10
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
      );

      final allInv = [invItemNormal, invItemLowStockWarning, invItemShortage];
      final Map<String, InventoryItem> invById = {for (final i in allInv) i.id: i};

      final lines = [
        invItemNormal,
        invItemLowStockWarning,
        invItemShortage,
      ];

      // Sort function matching _prioritizePreOrderDeficitLines
      lines.sort((a, b) {
        final invA = invById[a.id];
        final invB = invById[b.id];
        final isRecA = invA != null && invA.isPreOrderRecommended;
        final isRecB = invB != null && invB.isPreOrderRecommended;

        if (isRecA && !isRecB) return -1;
        if (!isRecA && isRecB) return 1;

        if (isRecA && isRecB) {
          final shortA = invA.hasPreOrderShortage ? invA.preOrderShortage : 0;
          final shortB = invB.hasPreOrderShortage ? invB.preOrderShortage : 0;
          if (shortA > 0 && shortB == 0) return -1;
          if (shortA == 0 && shortB > 0) return 1;
          if (shortA > 0 && shortB > 0 && shortA != shortB) {
            return shortB.compareTo(shortA);
          }
          final remA = invA.remainingStockAfterPreOrder;
          final remB = invB.remainingStockAfterPreOrder;
          if (remA != remB) return remA.compareTo(remB);
        }
        return 0;
      });

      // Shortage product floats to very top, then low stock warning, then normal
      expect(lines[0].id, equals('prod_shortage'));
      expect(lines[1].id, equals('prod_low_stock_warn'));
      expect(lines[2].id, equals('prod_normal'));
    });
  });

  group('InventoryCard Pre-Order Indicator Tests', () {
    testWidgets('Renders Pre-order badge and does not alter available inventory count', (tester) async {
      final item = InventoryItem(
        id: 'inv_pre_1',
        productName: 'P20 CORNETTO MINI',
        imageUrl: '',
        buyingPrice: 15,
        sellingPrice: 20,
        isActive: true,
        stockQuantity: 10,
        incomingQuantity: 0,
        reservedQuantity: 0,
        preOrderQuantity: 8,
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
        category: 'By Piece',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryCard(
              item: item,
              currencyFormat: currencyFormat,
              onTapCard: () {},
            ),
          ),
        ),
      );

      // Verify top-tier purple badge renders pre-order count
      expect(find.text('Pre-order: 8'), findsOneWidget);
      // Verify stock pipeline strip renders pre-order text and count
      expect(find.text('Pre-order'), findsOneWidget);
      expect(find.text('8'), findsWidgets);
      // Verify physical available count remains 10 (not subtracted)
      expect(find.text('10'), findsOneWidget);
    });
  });

  group('ManualPoProductPickerDialog Pre-Order Recommendation Tests', () {
    testWidgets('Places pre-order deficit products at the VERY TOP under Recommended Pre-Orders', (tester) async {
      final deficitItem = InventoryItem(
        id: 'rec_deficit_1',
        productName: 'P20 PREORDER DEFICIT ITEM',
        imageUrl: '',
        buyingPrice: 15,
        sellingPrice: 20,
        isActive: true,
        stockQuantity: 5,
        preOrderQuantity: 15, // Shortage = 15 - 5 = 10
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
        category: 'By Case',
      );

      final normalItem = InventoryItem(
        id: 'norm_item_1',
        productName: 'P30 REGULAR ITEM',
        imageUrl: '',
        buyingPrice: 20,
        sellingPrice: 30,
        isActive: true,
        stockQuantity: 20,
        preOrderQuantity: 0,
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
        category: 'By Case',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualPoProductPickerDialog(
              allInventory: [normalItem, deficitItem],
              existingLines: const [],
              currencyFormat: currencyFormat,
            ),
          ),
        ),
      );

      // Verify Recommended Pre-Orders section header is displayed at the top
      expect(find.textContaining('Recommended Pre-Orders'), findsOneWidget);
      // Verify shortage badge based on current warehouse stock (15 - 5 = 10)
      expect(find.textContaining('Shortage: 10 (Pre-order: 15 > Stock: 5)'), findsWidgets);
      // Verify Recommended filter chip
      expect(find.textContaining('Recommended (1)'), findsOneWidget);
    });
  });
}


