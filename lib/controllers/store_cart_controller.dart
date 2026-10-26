import 'package:flutter/foundation.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/store_order.dart';

/// Single item in the store's ordering cart
class StoreCartItem {
  final SelectaProduct product;
  final String packaging; // PackagingType.piece or PackagingType.case_
  int quantity;

  StoreCartItem({
    required this.product,
    required this.packaging,
    this.quantity = 1,
  });

  bool get isPiece => packaging == 'Piece';

  double get unitPrice {
    final basePrice = product.sellingPrice;
    if (isPiece) {
      return basePrice;
    }
    // Case price = piece price * piecesPerCase
    final pieces = (product.piecesPerCase != null && product.piecesPerCase! > 0)
        ? product.piecesPerCase!
        : 1;
    return basePrice * pieces;
  }

  double get totalPrice => unitPrice * quantity;

  StoreOrderItem toStoreOrderItem() {
    return StoreOrderItem(
      productId: product.id,
      productName: product.productName,
      flavor: product.flavor,
      packaging: packaging,
      qtyOrdered: quantity,
      qtyApproved: quantity,
      unitPrice: unitPrice,
      totalPrice: totalPrice,
      piecesPerCase: product.piecesPerCase,
    );
  }
}

/// Global/Scoped cart controller for Store Self-Ordering
class StoreCartController extends ChangeNotifier {
  static final StoreCartController _instance = StoreCartController._internal();
  factory StoreCartController() => _instance;
  StoreCartController._internal();

  final List<StoreCartItem> _items = [];

  List<StoreCartItem> get items => List.unmodifiable(_items);

  int get totalItemCount => _items.fold(0, (sum, i) => sum + i.quantity);

  int get itemCount => totalItemCount;

  int get lineCount => _items.length;

  double get subtotal => _items.fold(0.0, (sum, i) => sum + i.totalPrice);

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  int getQuantity(String productId, String packaging) {
    for (final item in _items) {
      if (item.product.id == productId && item.packaging == packaging) {
        return item.quantity;
      }
    }
    return 0;
  }

  void addItem(SelectaProduct product, String packaging, {int quantity = 1}) {
    if (quantity <= 0) return;
    final index = _items.indexWhere(
      (i) => i.product.id == product.id && i.packaging == packaging,
    );

    if (index >= 0) {
      _items[index].quantity += quantity;
    } else {
      _items.add(StoreCartItem(
        product: product,
        packaging: packaging,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  void setQuantity(String productId, String packaging, int quantity) {
    final index = _items.indexWhere(
      (i) => i.product.id == productId && i.packaging == packaging,
    );

    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
    }
  }

  void removeItem(String productId, String packaging) {
    _items.removeWhere(
      (i) => i.product.id == productId && i.packaging == packaging,
    );
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  void loadFromStoreOrder(StoreOrder order, [List<SelectaProduct> catalog = const []]) {
    _items.clear();
    final productMap = {for (final p in catalog) p.id: p};

    for (final item in order.items) {
      final product = productMap[item.productId] ??
          SelectaProduct(
            id: item.productId,
            productName: item.productName,
            imageUrl: item.imageUrl,
            itemCode: item.productId,
            category: item.category,
            sellingPrice: item.unitPrice,
          );

      _items.add(StoreCartItem(
        product: product,
        packaging: item.packaging,
        quantity: item.qtyOrdered,
      ));
    }
    notifyListeners();
  }
}
