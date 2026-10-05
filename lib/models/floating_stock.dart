import 'package:selecta_ops/models/delivery.dart';

/// Type of floating inventory transaction.
enum FloatingTransactionType {
  /// Incoming stock from active/pending Purchase Orders.
  incoming,

  /// Outgoing stock reserved for active store orders / deliveries in transit.
  outgoing,
}

/// Represents a specific document or transaction that holds floating stock.
class FloatingTransaction {
  final String id;
  final FloatingTransactionType type;
  final String title;
  final String subtitle;
  final String status;
  final DateTime date;
  final int totalUnits;
  final List<OrderItem> items;

  const FloatingTransaction({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.date,
    required this.totalUnits,
    required this.items,
  });

  bool get isIncoming => type == FloatingTransactionType.incoming;
  bool get isOutgoing => type == FloatingTransactionType.outgoing;
}

/// Source reference linking a specific product line to its parent transaction.
class FloatingSourceRef {
  final String transactionId;
  final String title;
  final String subtitle;
  final String status;
  final DateTime date;
  final int quantity;
  final bool isIncoming;

  const FloatingSourceRef({
    required this.transactionId,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.date,
    required this.quantity,
    required this.isIncoming,
  });
}

/// An individual product SKU that currently has floating units (incoming or outgoing).
class FloatingProductItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String productSource; // 'selecta' | 'other'
  final String category;      // 'By Piece' | 'By Case' | ''
  final double buyingPrice;
  final double sellingPrice;
  final int stockQuantity;    // Physical on-hand stock
  final int incomingQuantity; // Going in (POs)
  final int reservedQuantity; // Going out (Deliveries)
  final List<FloatingSourceRef> incomingSources;
  final List<FloatingSourceRef> outgoingSources;

  const FloatingProductItem({
    required this.productId,
    required this.productName,
    required this.imageUrl,
    required this.productSource,
    required this.category,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.stockQuantity,
    required this.incomingQuantity,
    required this.reservedQuantity,
    this.incomingSources = const [],
    this.outgoingSources = const [],
  });

  /// Available units taking into account physical stock, incoming, and outgoing reservations.
  int get availableQuantity =>
      ((stockQuantity + incomingQuantity) - reservedQuantity) < 0
          ? 0
          : ((stockQuantity + incomingQuantity) - reservedQuantity);

  int get netFloatingDelta => incomingQuantity - reservedQuantity;
}

/// Aggregated dataset containing all active floating products and transactions.
class FloatingStockData {
  final List<FloatingProductItem> products;
  final List<FloatingTransaction> incomingTransactions;
  final List<FloatingTransaction> outgoingTransactions;
  final int totalIncomingUnits;
  final int totalReservedUnits;

  const FloatingStockData({
    required this.products,
    required this.incomingTransactions,
    required this.outgoingTransactions,
    required this.totalIncomingUnits,
    required this.totalReservedUnits,
  });

  int get netFloatingUnits => totalIncomingUnits - totalReservedUnits;
  int get incomingOrderCount => incomingTransactions.length;
  int get outgoingOrderCount => outgoingTransactions.length;
  int get affectedProductCount => products.length;

  static const empty = FloatingStockData(
    products: [],
    incomingTransactions: [],
    outgoingTransactions: [],
    totalIncomingUnits: 0,
    totalReservedUnits: 0,
  );
}
