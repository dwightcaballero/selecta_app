import 'dart:convert';

import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/purchaseorder.dart';

typedef ReceiptProduct = ({OrderItem item, int ordered, int received});

class ManualPurchaseReceipt {
  ManualPurchaseReceipt._(this.products, this.receivedItems, this.total);

  final List<ReceiptProduct> products;
  final List<OrderItem> receivedItems;
  final double total;

  factory ManualPurchaseReceipt.prepare(List<OrderItem> original, List<ManualReceiptLine> lines) {
    if (lines.isEmpty || lines.length != original.length) {
      throw StateError('The receipt must include every saved purchase order line.');
    }
    final merged = <String, ReceiptProduct>{};
    var total = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final item = original[i];
      if (jsonEncode(line.item.toJson()) != jsonEncode(item.toJson()) ||
          item.productId.isEmpty || item.effectiveQuantity <= 0 ||
          line.receivedQuantity < 0 || line.receivedQuantity > item.effectiveQuantity ||
          (line.receivedQuantity < item.effectiveQuantity && line.shortageReason.trim().isEmpty)) {
        throw StateError('Invalid receipt line for ${item.productName}.');
      }
      final key = '${item.productSource}:${item.productId}';
      final previous = merged[key];
      merged[key] = (
        item: item,
        ordered: (previous?.ordered ?? 0) + item.effectiveQuantity,
        received: (previous?.received ?? 0) + line.receivedQuantity,
      );
      total += line.receivedQuantity * item.buyingPrice;
    }
    final receivedItems = merged.values.where((entry) => entry.received > 0)
        .map((entry) => entry.item.copyWith(
          orderedQuantity: entry.ordered,
          pickedQuantity: entry.received,
          isPicked: true,
        )).toList();
    if (receivedItems.isEmpty) throw StateError('At least one unit must be received.');
    if (merged.length > 150) throw StateError('A manual receipt cannot contain more than 150 distinct products.');
    return ManualPurchaseReceipt._(merged.values.toList(), receivedItems, total);
  }
}
