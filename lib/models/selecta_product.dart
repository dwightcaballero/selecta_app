import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Selecta product in the catalog.
class SelectaProduct {
  final String id;
  final String productName;
  final String imageUrl;
  final String itemCode;
  final String barcode;
  final double buyingPrice;
  final double sellingPrice;
  final String category;
  final String tag;
  final bool isActive;
  final int stockQuantity;
  final int incomingQuantity;
  final int reservedQuantity;
  final int lowStockThreshold;
  final int maxStock;
  final int? boPiecesPerCase;
  final double? badOrderPricePerPiece;
  final String? subCategoryId;
  final Timestamp? importedAt;
  final Timestamp? updatedAt;

  const SelectaProduct({
    required this.id,
    required this.productName,
    required this.imageUrl,
    required this.itemCode,
    this.barcode = '',
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
    required this.category,
    this.tag = '',
    this.isActive = true,
    this.stockQuantity = 0,
    this.incomingQuantity = 0,
    this.reservedQuantity = 0,
    this.lowStockThreshold = 10,
    this.maxStock = 0,
    this.boPiecesPerCase,
    this.badOrderPricePerPiece,
    this.subCategoryId,
    this.importedAt,
    this.updatedAt,
  });

  /// Backward-compatible price accessor (selling price).
  double get price => sellingPrice;

  /// Flavor or variant description.
  String get flavor => '';

  /// Pieces per case for case packaging (legacy stub kept null for store app isolation).
  int? get piecesPerCase => null;

  /// Whether the product is categorized "By Case".
  bool get isCaseProduct => category == 'By Case';

  /// Whether the product has a valid configured pieces-per-case (whole number from 2 to 999).
  bool get hasValidBoPiecesPerCase =>
      boPiecesPerCase != null && boPiecesPerCase! >= 2 && boPiecesPerCase! <= 999;

  /// Whether the product is ready for bad order refund computation.
  /// By Piece products are always ready. By Case products require 2..999 pieces-per-case.
  bool get isBoPricingReady => !isCaseProduct || hasValidBoPiecesPerCase;

  /// Store refund per piece (dealer -> store), based on selling price.
  /// For By Piece: selling price. For By Case: selling price / boPiecesPerCase.
  /// Returns 0.0 when not ready.
  double get storeRefundPerPiece {
    if (!isBoPricingReady) return 0.0;
    return isCaseProduct ? (sellingPrice / boPiecesPerCase!) : sellingPrice;
  }

  /// Supplier refund per piece (supplier -> dealer), based on buying price.
  /// For By Piece: buying price. For By Case: buying price / boPiecesPerCase.
  /// Returns 0.0 when not ready.
  double get supplierRefundPerPiece {
    if (!isBoPricingReady) return 0.0;
    return isCaseProduct ? (buyingPrice / boPiecesPerCase!) : buyingPrice;
  }

  /// Gross margin amount (sellingPrice - buyingPrice).
  double get margin => sellingPrice - buyingPrice;

  /// Margin percentage relative to buying price.
  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  /// Physical unreserved stock in the warehouse (Current Stock - Reserved Stock).
  int get netPhysicalStock => stockQuantity - reservedQuantity;

  /// Available stock = Current stock + Incoming Stock - Reserved stock.
  int get availableQuantity =>
      ((stockQuantity + incomingQuantity) - reservedQuantity) < 0
          ? 0
          : ((stockQuantity + incomingQuantity) - reservedQuantity);

  /// True when physical stock in warehouse is 0 or less.
  bool get isOutOfStock => stockQuantity <= 0;

  /// True when both physical stock and incoming stock are exhausted or committed.
  bool get isAvailableOutOfStock => availableQuantity <= 0;

  /// Low Stock indicator based strictly on Current stock - Reserved stock <= lowStockThreshold.
  /// Does NOT include incoming stock in the computation.
  bool get isLowStock => stockQuantity > 0 && netPhysicalStock <= lowStockThreshold;

  /// Total inventory value at buying cost.
  double get stockCostValue => stockQuantity * buyingPrice;

  /// Total inventory value at selling price.
  double get stockRetailValue => stockQuantity * sellingPrice;

  /// Effective bad order price per individual piece (store refund).
  /// Kept for backward compatibility during migration.
  double get boPricePerPiece =>
      isBoPricingReady ? storeRefundPerPiece : (badOrderPricePerPiece ?? 0.0);

  /// Whether the product has a valid configured bad order price.
  /// Kept for backward compatibility during migration.
  bool get isBoPriceConfigured => isBoPricingReady;

  static SelectaProduct empty() => const SelectaProduct(
        id: '',
        productName: '',
        imageUrl: '',
        itemCode: '',
        barcode: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
        category: '',
        tag: '',
        isActive: true,
        stockQuantity: 0,
        incomingQuantity: 0,
        reservedQuantity: 0,
        lowStockThreshold: 10,
        maxStock: 0,
        boPiecesPerCase: null,
        badOrderPricePerPiece: null,
      );

  factory SelectaProduct.fromJson(String id, Map<String, Object?> json) {
    final legacyPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    final buyingPrice = (json['buyingPrice'] as num?)?.toDouble() ?? legacyPrice;
    final sellingPrice = (json['sellingPrice'] as num?)?.toDouble() ?? legacyPrice;

    final rawCategory = (json['category'] as String? ?? '').trim();
    final isCase = rawCategory.toLowerCase().contains('case');
    final category = isCase ? 'By Case' : 'By Piece';

    return SelectaProduct(
      id: id,
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      itemCode: json['itemCode'] as String? ?? '',
      barcode: (json['barcode'] as String? ?? '').trim(),
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: category,
      tag: (json['tag'] as String? ?? '').trim(),
      isActive: json['isActive'] as bool? ?? true,
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      incomingQuantity: (json['incomingQuantity'] as num?)?.toInt() ?? 0,
      reservedQuantity: (json['reservedQuantity'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 10,
      maxStock: (json['maxStock'] as num?)?.toInt() ?? 0,
      boPiecesPerCase: (json['boPiecesPerCase'] as num?)?.toInt(),
      badOrderPricePerPiece: (json['badOrderPricePerPiece'] as num?)?.toDouble(),
      subCategoryId: json['subCategoryId'] as String?,
      importedAt: json['importedAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  factory SelectaProduct.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      return SelectaProduct.fromJson(document.id, document.data()!.cast<String, Object?>());
    }
    return SelectaProduct.empty();
  }

  SelectaProduct copyWith({
    String? id,
    String? productName,
    String? imageUrl,
    String? itemCode,
    String? barcode,
    double? buyingPrice,
    double? sellingPrice,
    String? category,
    String? tag,
    bool? isActive,
    int? stockQuantity,
    int? incomingQuantity,
    int? reservedQuantity,
    int? lowStockThreshold,
    int? maxStock,
    int? boPiecesPerCase,
    bool clearBoPiecesPerCase = false,
    double? badOrderPricePerPiece,
    String? subCategoryId,
    bool clearSubCategoryId = false,
    Timestamp? importedAt,
    Timestamp? updatedAt,
  }) {
    return SelectaProduct(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      itemCode: itemCode ?? this.itemCode,
      barcode: barcode ?? this.barcode,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      isActive: isActive ?? this.isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      incomingQuantity: incomingQuantity ?? this.incomingQuantity,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      maxStock: maxStock ?? this.maxStock,
      boPiecesPerCase: clearBoPiecesPerCase ? null : (boPiecesPerCase ?? this.boPiecesPerCase),
      badOrderPricePerPiece: badOrderPricePerPiece ?? this.badOrderPricePerPiece,
      subCategoryId: clearSubCategoryId ? null : (subCategoryId ?? this.subCategoryId),
      importedAt: importedAt ?? this.importedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Creates or updates a dealer's [SelectaProduct] from the master [AdminSelectaProduct],
  /// preserving the dealer's local [isActive] status and stock levels if already present.
  factory SelectaProduct.fromAdminProduct({
    required String id,
    required String productName,
    required String imageUrl,
    required double buyingPrice,
    required double sellingPrice,
    bool isActive = true,
    int stockQuantity = 0,
    int incomingQuantity = 0,
    int reservedQuantity = 0,
    int lowStockThreshold = 10,
    int maxStock = 0,
    String itemCode = '',
    String barcode = '',
    String category = '',
    String tag = '',
    int? boPiecesPerCase,
    double? badOrderPricePerPiece,
    String? subCategoryId,
    Timestamp? importedAt,
    Timestamp? updatedAt,
  }) {
    return SelectaProduct(
      id: id,
      productName: productName,
      imageUrl: imageUrl,
      itemCode: itemCode,
      barcode: barcode,
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: category,
      tag: tag,
      isActive: isActive,
      stockQuantity: stockQuantity,
      incomingQuantity: incomingQuantity,
      reservedQuantity: reservedQuantity,
      lowStockThreshold: lowStockThreshold,
      maxStock: maxStock,
      boPiecesPerCase: boPiecesPerCase,
      badOrderPricePerPiece: badOrderPricePerPiece,
      subCategoryId: subCategoryId,
      importedAt: importedAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productName': productName,
      'imageUrl': imageUrl,
      'itemCode': itemCode,
      'barcode': barcode,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'price': sellingPrice, // backward compatibility
      'category': category,
      'tag': tag,
      'isActive': isActive,
      'stockQuantity': stockQuantity,
      'incomingQuantity': incomingQuantity,
      'reservedQuantity': reservedQuantity,
      'lowStockThreshold': lowStockThreshold,
      'maxStock': maxStock,
      if (isCaseProduct && boPiecesPerCase != null) 'boPiecesPerCase': boPiecesPerCase,
      if (subCategoryId != null) 'subCategoryId': subCategoryId,
      'importedAt': importedAt,
      'updatedAt': updatedAt,
    };
  }
}
