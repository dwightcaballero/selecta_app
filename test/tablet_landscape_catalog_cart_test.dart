import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/dto/dashboard_dto.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorder_catalog_page.dart';
import 'package:selecta_ops/views/widgets/dashboard/dashboard_sidebar.dart';

void main() {
  final sampleCatalog = [
    InventoryItem(
      id: 'sel_1',
      productName: 'SELECTA CORNETTO CLASSIC',
      imageUrl: '',
      buyingPrice: 20.0,
      sellingPrice: 25.0,
      isActive: true,
      stockQuantity: 50,
      preOrderQuantity: 0,
      lowStockThreshold: 5,
      source: InventoryProductSource.selecta,
      category: 'By Piece',
    ),
    InventoryItem(
      id: 'sel_2',
      productName: 'SELECTA 3IN1 CASE TUB',
      imageUrl: '',
      buyingPrice: 150.0,
      sellingPrice: 180.0,
      isActive: true,
      stockQuantity: 20,
      preOrderQuantity: 0,
      lowStockThreshold: 5,
      source: InventoryProductSource.selecta,
      category: 'By Case',
    ),
  ];

  group('Tablet Landscape vs Mobile View Responsiveness Tests', () {
    testWidgets('ScreenSize.isTabletLandscape returns false on phone portrait and landscape', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final isLandscape = ScreenSize.isTabletLandscape(context);
              return Text('Landscape: $isLandscape');
            },
          ),
        ),
      );

      // Default flutter test window size is 800x600 (not width >= 900)
      expect(find.text('Landscape: false'), findsOneWidget);
    });

    testWidgets('ScreenSize.isTabletLandscape returns true on tablet landscape (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final isLandscape = ScreenSize.isTabletLandscape(context);
              return Text('Landscape: $isLandscape');
            },
          ),
        ),
      );

      expect(find.text('Landscape: true'), findsOneWidget);
    });

    testWidgets('PurchaseOrderCatalogPage renders dual-pane on tablet landscape with products on left and cart on right', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseOrderCatalogPage(
            allInventory: sampleCatalog,
            existingLines: const [],
            isDirectCreationFlow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On tablet landscape:
      // Pinned Right Cart Pane is rendered
      expect(find.textContaining('Order Cart'), findsOneWidget);
      expect(find.text('No items in order'), findsOneWidget);
      expect(find.text('Select products on the left to add to Purchase Order.'), findsOneWidget);

      // Left pane has catalog search & items
      expect(find.text('SELECTA CORNETTO CLASSIC'), findsOneWidget);
      expect(find.text('SELECTA 3IN1 CASE TUB'), findsOneWidget);

      // Tap on a product card on the left pane to add it to cart
      await tester.tap(find.text('SELECTA CORNETTO CLASSIC'));
      await tester.pumpAndSettle();

      // Cart pane on the right immediately updates with the added item!
      expect(find.textContaining('Order Cart (1 SKU • 1 units)'), findsOneWidget);
      expect(find.text('Total Buying Cost:'), findsOneWidget);
      expect(find.text('Create Order (1)'), findsOneWidget);
    });

    testWidgets('PurchaseOrderCatalogPage on mobile portrait (390x844) renders standard mobile layout with sticky bottom bar', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseOrderCatalogPage(
            allInventory: sampleCatalog,
            existingLines: const [],
            isDirectCreationFlow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In phone portrait:
      // Tablet cart pane is NOT present
      expect(find.text('No items in order'), findsNothing);
      expect(find.text('Select products on the left to add to Purchase Order.'), findsNothing);

      // Sticky bottom bar IS present
      expect(find.textContaining('0 items • 0 units'), findsOneWidget);
      expect(find.text('Create Order'), findsOneWidget);
    });

    testWidgets('PurchaseOrderCatalogPage on mobile phone rotated to landscape (844x390) preserves mobile layout', (tester) async {
      // Phone rotated horizontally: width 844 is < 900 and shortestSide 390 is < 600
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseOrderCatalogPage(
            allInventory: sampleCatalog,
            existingLines: const [],
            isDirectCreationFlow: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile phone in landscape must NOT trigger tablet dual pane
      expect(find.text('No items in order'), findsNothing);
      expect(find.text('Select products on the left to add to Purchase Order.'), findsNothing);

      // Sticky bottom bar remains
      expect(find.textContaining('0 items • 0 units'), findsOneWidget);
      expect(find.text('Create Order'), findsOneWidget);
    });

    testWidgets('DashboardSidebar renders alongside another ScrollView without PrimaryScrollController exception', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                DashboardSidebar(
                  currentUser: null,
                  isDealer: true,
                  isSyncing: false,
                  dashboardDTO: DashboardDTO.empty(),
                  merchBlitzCountStream: const Stream<int>.empty(),
                  tasksCountStream: const Stream<int>.empty(),
                  onSync: () {},
                  onLogout: () {},
                  onNavigate: (_) async {},
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(50, (i) => Text('Item $i')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Verify no assertion error was thrown during layout and scheduler callbacks
      await tester.pumpAndSettle();
      expect(find.byType(DashboardSidebar), findsOneWidget);
      expect(find.text('OPERATIONS'), findsOneWidget);
      expect(find.text('Item 0'), findsOneWidget);
    });

    testWidgets('DashboardSidebar header height matches topPadding + 72 toolbar height for CustomAppbar alignment', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
            child: Scaffold(
              body: DashboardSidebar(
                currentUser: null,
                isDealer: true,
                isSyncing: false,
                dashboardDTO: DashboardDTO.empty(),
                merchBlitzCountStream: const Stream<int>.empty(),
                tasksCountStream: const Stream<int>.empty(),
                onSync: () {},
                onLogout: () {},
                onNavigate: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Total header height: topPadding (24) + toolbarHeight (72) = 96.0
      final headerFinder = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 96.0);
      expect(headerFinder, findsOneWidget);
    });

    testWidgets('DashboardSidebar renders unified navigation tabs when tab properties are provided', (tester) async {
      int selectedTab = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardSidebar(
              currentUser: null,
              isDealer: true,
              isSyncing: false,
              dashboardDTO: DashboardDTO.empty(),
              merchBlitzCountStream: const Stream<int>.empty(),
              tasksCountStream: const Stream<int>.empty(),
              currentTabIndex: selectedTab,
              onTabSelected: (index) => selectedTab = index,
              purchaseOrdersAwaitingCountStream: const Stream<int>.empty(),
              pendingPicklistsCountStream: const Stream<int>.empty(),
              pendingDeliveriesCountStream: const Stream<int>.empty(),
              onSync: () {},
              onLogout: () {},
              onNavigate: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Main Navigation section
      expect(find.text('MAIN NAVIGATION'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Restock'), findsOneWidget);
      expect(find.text('PickLists'), findsOneWidget);
      expect(find.text('Deliveries'), findsOneWidget);

      // Tap on Restock tab
      await tester.tap(find.text('Restock'));
      expect(selectedTab, 1);
    });
  });
}



