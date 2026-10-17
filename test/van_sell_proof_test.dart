import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/van_sell_controller.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/van_load_service.dart';

class FakeVanLoadService extends Fake implements VanLoadService {}
class FakeDeliveryService extends Fake implements DeliveryService {}
class FakeHapiStoreService extends Fake implements HapiStoreService {}
class FakeFirebaseFirestore extends Fake implements FirebaseFirestore {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Van Sell Proof of Van Selling Requirements', () {
    late VanSellController controller;
    late VanLoad testVanLoad;
    late Hapistore testStore;
    late List<OrderItem> testItems;

    setUp(() {
      controller = VanSellController(
        vanLoadService: FakeVanLoadService(),
        deliveryService: FakeDeliveryService(),
        hapiStoreService: FakeHapiStoreService(),
        firestore: FakeFirebaseFirestore(),
      );

      testVanLoad = VanLoad(
        id: 'load_123',
        date: Timestamp.now(),
        createdBy: 'Salesman Test',
        createdDate: Timestamp.now(),
        lastUpdatedBy: 'Salesman Test',
        lastUpdatedDate: Timestamp.now(),
        items: [
          VanLoadItem(
            productId: 'prod_1',
            productName: 'Selecta Cornetto Chocolate',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 50,
            soldQuantity: 0,
            buyingPrice: 25.0,
            sellingPrice: 30.0,
          ),
        ],
      );

      testStore = Hapistore(
        storeName: 'Test Sari-Sari Store',
        storeAddress: '123 Main St',
        storeContact: '09123456789',
        openingDate: Timestamp.now(),
      );

      testItems = [
        const OrderItem(
          productId: 'prod_1',
          productName: 'Selecta Cornetto Chocolate',
          category: 'By Piece',
          productSource: 'selecta',
          sellingPrice: 30.0,
          orderedQuantity: 5,
          pickedQuantity: 5,
          isPicked: true,
        ),
      ];
    });

    test('completeVanSale throws ArgumentError when imagePath is empty', () async {
      expect(
        () => controller.completeVanSale(
          vanLoad: testVanLoad,
          store: testStore,
          items: testItems,
          paymentMethod: 'Cash',
          cashAmount: 150.0,
          onlineAmount: 0.0,
          creditAmount: 0.0,
          imagePath: '',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Proof of van selling photo is required'),
        )),
      );
    });

    test('completeVanSale throws ArgumentError when imagePath is whitespace only', () async {
      expect(
        () => controller.completeVanSale(
          vanLoad: testVanLoad,
          store: testStore,
          items: testItems,
          paymentMethod: 'Cash',
          cashAmount: 150.0,
          onlineAmount: 0.0,
          creditAmount: 0.0,
          imagePath: '   ',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Proof of van selling photo is required'),
        )),
      );
    });
  });
}
