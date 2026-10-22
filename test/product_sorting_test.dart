import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/product_sort_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/product_sort_doc.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/product_sort_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProductSortService sortService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sortService = ProductSortService.instance;
    sortService.resetForTesting();
  });

  tearDown(() {
    sortService.resetForTesting();
  });

  group('Product Sorting Comparator - Mode "srp"', () {
    test('orders by extracted SRP ascending, then alphabetically by name', () {
      sortService.configureForTesting(
        sortMode: 'srp',
        subCategories: [],
        sortDoc: null,
      );

      final p1 = {'name': 'Selecta Super Thick Vanilla 750ml P150', 'price': 150.0, 'id': 'p1'};
      final p2 = {'name': 'Selecta Cornetto Chocolate P35', 'price': 35.0, 'id': 'p2'};
      final p3 = {'name': 'Selecta Cornetto Vanilla P35', 'price': 35.0, 'id': 'p3'};
      final p4 = {'name': 'Selecta Magnum Almond P70', 'price': 70.0, 'id': 'p4'};

      final list = [p1, p2, p3, p4];
      list.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
          ));

      expect(list[0]['id'], 'p2'); // Cornetto Chocolate P35
      expect(list[1]['id'], 'p3'); // Cornetto Vanilla P35
      expect(list[2]['id'], 'p4'); // Magnum Almond P70
      expect(list[3]['id'], 'p1'); // Super Thick Vanilla P150
    });
  });

  group('Product Sorting Comparator - Mode "custom"', () {
    final subCatCones = SubCategory(
      id: 'sub_cones',
      name: 'Cones',
      category: 'By Piece',
      order: 0,
      isActive: true,
    );
    final subCatTubs = SubCategory(
      id: 'sub_tubs',
      name: 'Tubs',
      category: 'By Piece',
      order: 1,
      isActive: true,
    );
    final subCatSticks = SubCategory(
      id: 'sub_sticks',
      name: 'Sticks',
      category: 'By Piece',
      order: 2,
      isActive: false, // Inactive!
    );

    final sortDoc = ProductSortDoc(
      dealerId: 'dealer_1',
      byPiece: {
        'sub_cones': ['p_cornetto_vanilla', 'p_cornetto_choco'],
        'sub_tubs': ['p_tub_vanilla', 'p_tub_choco'],
        'sub_sticks': ['p_magnum_almond'],
      },
    );

    test('orders by sub-category order (Level 1) then product index (Level 2)', () {
      sortService.configureForTesting(
        sortMode: 'custom',
        subCategories: [subCatCones, subCatTubs],
        sortDoc: sortDoc,
      );

      final pTub1 = {'id': 'p_tub_vanilla', 'name': 'Super Thick Vanilla 750ml P150', 'price': 150.0};
      final pTub2 = {'id': 'p_tub_choco', 'name': 'Super Thick Chocolate 750ml P150', 'price': 150.0};
      final pCone1 = {'id': 'p_cornetto_vanilla', 'name': 'Cornetto Vanilla P35', 'price': 35.0};
      final pCone2 = {'id': 'p_cornetto_choco', 'name': 'Cornetto Chocolate P35', 'price': 35.0};

      final items = [pTub2, pCone2, pTub1, pCone1];
      items.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
            categoryA: 'By Piece',
            categoryB: 'By Piece',
          ));

      // Cones (order 0): p_cornetto_vanilla (idx 0), p_cornetto_choco (idx 1)
      // Tubs (order 1): p_tub_vanilla (idx 0), p_tub_choco (idx 1)
      expect(items.map((i) => i['id']).toList(), [
        'p_cornetto_vanilla',
        'p_cornetto_choco',
        'p_tub_vanilla',
        'p_tub_choco',
      ]);
    });

    test('places unassigned products at the bottom, ordered by SRP then name', () {
      sortService.configureForTesting(
        sortMode: 'custom',
        subCategories: [subCatCones, subCatTubs],
        sortDoc: sortDoc,
      );

      final assignedCone = {'id': 'p_cornetto_choco', 'name': 'Cornetto Chocolate P35', 'price': 35.0};
      final unassigned1 = {'id': 'p_unassigned_cheap', 'name': 'Ice Pop Lemon P15', 'price': 15.0};
      final unassigned2 = {'id': 'p_unassigned_expensive', 'name': 'Ice Cream Cake P300', 'price': 300.0};

      final items = [unassigned2, assignedCone, unassigned1];
      items.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
            categoryA: 'By Piece',
            categoryB: 'By Piece',
          ));

      expect(items.map((i) => i['id']).toList(), [
        'p_cornetto_choco', // assigned comes first
        'p_unassigned_cheap', // unassigned: P15
        'p_unassigned_expensive', // unassigned: P300
      ]);
    });

    test('treats products in inactive or deleted sub-categories as unassigned', () {
      sortService.configureForTesting(
        sortMode: 'custom',
        subCategories: [subCatCones, subCatTubs, subCatSticks], // Sticks is isActive = false
        sortDoc: sortDoc,
      );

      final assignedCone = {'id': 'p_cornetto_choco', 'name': 'Cornetto Chocolate P35', 'price': 35.0};
      final inInactiveSubCat = {'id': 'p_magnum_almond', 'name': 'Magnum Almond P70', 'price': 70.0};

      final items = [inInactiveSubCat, assignedCone];
      items.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
            categoryA: 'By Piece',
            categoryB: 'By Piece',
          ));

      // inInactiveSubCat is treated as unassigned, so assignedCone comes first
      expect(items.first['id'], 'p_cornetto_choco');
      expect(items.last['id'], 'p_magnum_almond');
    });

    test('falls back to SRP when custom data is empty', () {
      sortService.configureForTesting(
        sortMode: 'custom',
        subCategories: [],
        sortDoc: null,
      );

      final p1 = {'id': 'p1', 'name': 'Vanilla P150', 'price': 150.0};
      final p2 = {'id': 'p2', 'name': 'Chocolate P35', 'price': 35.0};

      final items = [p1, p2];
      items.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
          ));

      expect(items.map((i) => i['id']).toList(), ['p2', 'p1']);
    });

    test('honors category hierarchy between By Case and By Piece', () {
      sortService.configureForTesting(
        sortMode: 'custom',
        subCategories: [
          const SubCategory(id: 'c_tub', name: 'Bulk Tub Cases', category: 'By Case', order: 0),
          const SubCategory(id: 'p_cone', name: 'Cones', category: 'By Piece', order: 0),
        ],
        sortDoc: const ProductSortDoc(
          dealerId: 'dealer_1',
          byCase: {'c_tub': ['case_tub_1']},
          byPiece: {'p_cone': ['piece_cone_1']},
        ),
      );

      final pieceItem = {
        'id': 'piece_cone_1',
        'name': 'Cornetto P35',
        'price': 35.0,
        'category': 'By Piece'
      };
      final caseItem = {
        'id': 'case_tub_1',
        'name': 'Case Vanilla P1500',
        'price': 1500.0,
        'category': 'By Case'
      };

      final items = [pieceItem, caseItem];
      items.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a['name'] as String,
            priceA: a['price'] as double,
            nameB: b['name'] as String,
            priceB: b['price'] as double,
            productIdA: a['id'] as String,
            productIdB: b['id'] as String,
            categoryA: a['category'] as String,
            categoryB: b['category'] as String,
          ));

      // 'By Case' comes before 'By Piece'
      expect(items.first['id'], 'case_tub_1');
      expect(items.last['id'], 'piece_cone_1');
    });
  });

  group('ProductSortController Logic', () {
    test('sub-category creation, rename, activation, deletion, and reorder', () {
      final controller = ProductSortController();
      controller.initialize(
        subCategories: [],
        sortDoc: ProductSortDoc.empty('dealer_test'),
      );

      // 1. Create sub-categories
      final c1 = controller.createSubCategory(name: 'Cones', category: 'By Piece');
      final c2 = controller.createSubCategory(name: 'Tubs', category: 'By Piece');
      final c3 = controller.createSubCategory(name: 'Sticks', category: 'By Piece');

      expect(c1.order, 0);
      expect(c2.order, 1);
      expect(c3.order, 2);
      expect(controller.hasUnsavedChanges, isTrue);

      // 2. Rename sub-category
      controller.renameSubCategory(c1.id, 'Delicious Cones');
      expect(controller.subCategories.firstWhere((s) => s.id == c1.id).name, 'Delicious Cones');

      // 3. Toggle active
      controller.toggleSubCategoryActive(c2.id, false);
      expect(controller.subCategories.firstWhere((s) => s.id == c2.id).isActive, isFalse);

      // 4. Reorder sub-categories (move Sticks from index 2 to index 0)
      controller.reorderSubCategories('By Piece', 2, 0);
      final reordered = controller.getSubCategoriesForCategory('By Piece');
      expect(reordered[0].id, c3.id); // Sticks
      expect(reordered[0].order, 0);
      expect(reordered[1].id, c1.id); // Cones
      expect(reordered[1].order, 1);

      // 5. Delete sub-category
      controller.deleteSubCategory(c2.id, 'By Piece');
      expect(controller.subCategories.any((s) => s.id == c2.id), isFalse);
    });

    test('product assignment, reorder, move, and deletion to unassigned', () {
      final controller = ProductSortController();
      final subCat = const SubCategory(id: 'cat_cones', name: 'Cones', category: 'By Piece', order: 0);
      final subCat2 = const SubCategory(id: 'cat_tubs', name: 'Tubs', category: 'By Piece', order: 1);

      controller.initialize(
        subCategories: [subCat, subCat2],
        sortDoc: ProductSortDoc.empty('dealer_test'),
      );

      // 1. Add products to subCat
      controller.addProductToSubCategory(category: 'By Piece', subCategoryId: 'cat_cones', productId: 'p1');
      controller.addProductToSubCategory(category: 'By Piece', subCategoryId: 'cat_cones', productId: 'p2');
      controller.addProductToSubCategory(category: 'By Piece', subCategoryId: 'cat_cones', productId: 'p3');

      expect(controller.sortDoc.byPiece['cat_cones'], ['p1', 'p2', 'p3']);

      // 2. Reorder products within sub-category (move p3 to index 0)
      controller.reorderProductsInSubCategory(
        category: 'By Piece',
        subCategoryId: 'cat_cones',
        oldIndex: 2,
        newIndex: 0,
      );
      expect(controller.sortDoc.byPiece['cat_cones'], ['p3', 'p1', 'p2']);

      // 3. Move product p1 to subCat2
      controller.moveProduct(
        category: 'By Piece',
        fromSubCategoryId: 'cat_cones',
        toSubCategoryId: 'cat_tubs',
        productId: 'p1',
      );
      expect(controller.sortDoc.byPiece['cat_cones'], ['p3', 'p2']);
      expect(controller.sortDoc.byPiece['cat_tubs'], ['p1']);

      // 4. Ensure single sub-category membership constraint:
      // Adding p3 to cat_tubs removes it from cat_cones
      controller.addProductToSubCategory(category: 'By Piece', subCategoryId: 'cat_tubs', productId: 'p3');
      expect(controller.sortDoc.byPiece['cat_cones'], ['p2']);
      expect(controller.sortDoc.byPiece['cat_tubs'], ['p1', 'p3']);

      // 5. Deleting sub-category moves its products to unassigned
      controller.deleteSubCategory('cat_tubs', 'By Piece');
      expect(controller.sortDoc.byPiece.containsKey('cat_tubs'), isFalse);
    });
  });

  group('Configuration & Offline Cache Serialization', () {
    test('Configuration model serializes and deserializes productSortMode and subCategories', () {
      final sub = SubCategory(
        id: 'sub_test',
        name: 'Sandwiches',
        category: 'By Piece',
        order: 2,
        isActive: true,
      );

      final config = Configuration.empty().copyWith(
        productSortMode: 'custom',
        subCategories: [sub],
      );

      final json = config.toJson();
      expect(json['productSortMode'], 'custom');
      expect(json['subCategories'], isList);
      final list = json['subCategories'] as List;
      expect(list.length, 1);
      expect((list.first as Map)['name'], 'Sandwiches');

      final deserialized = Configuration.fromJson(json);
      expect(deserialized.productSortMode, 'custom');
      expect(deserialized.subCategories.length, 1);
      expect(deserialized.subCategories.first.name, 'Sandwiches');
      expect(deserialized.subCategories.first.order, 2);
    });

    test('ProductSortDoc serializes and deserializes byPiece and byCase correctly', () {
      final doc = ProductSortDoc(
        dealerId: 'dealer_123',
        byPiece: {'sub_1': ['p1', 'p2']},
        byCase: {'sub_2': ['c1', 'c2']},
        updatedBy: 'tester@selecta.ph',
      );

      final json = doc.toJson();
      final fromJson = ProductSortDoc.fromJson('dealer_123', json);

      expect(fromJson.dealerId, 'dealer_123');
      expect(fromJson.byPiece['sub_1'], ['p1', 'p2']);
      expect(fromJson.byCase['sub_2'], ['c1', 'c2']);
      expect(fromJson.updatedBy, 'tester@selecta.ph');
    });
  });
}
