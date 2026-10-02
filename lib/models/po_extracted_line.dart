/// Represents a single line item extracted from the document in its exact scanned sequence.
class PoExtractedLine {
  String productId;
  String productName;
  String imageUrl;
  String productSource;
  String category;
  String tag;
  double buyingPrice;
  double sellingPrice;
  int quantity;
  String rawDocText;
  bool isIncorrect;
  bool isCorrected;

  PoExtractedLine({
    required this.productId,
    required this.productName,
    required this.imageUrl,
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    required this.buyingPrice,
    this.sellingPrice = 0.0,
    required this.quantity,
    this.rawDocText = '',
    this.isIncorrect = false,
    this.isCorrected = false,
  });

  double get lineTotal => quantity * buyingPrice;
}

/// Represents the type of discrepancy between ordered PO quantity and official invoice quantity.
enum PoDiscrepancyType {
  matched, // Ordered == Invoiced
  shortage, // Invoiced < Ordered (and Invoiced > 0)
  missing, // Invoiced == 0 (PO had > 0)
  excess, // Invoiced > Ordered (and Ordered > 0)
  extra, // Invoiced > 0 (PO had 0)
}

/// Represents a matched or discrepant line between the original P.O. and the official invoice.
class PoInvoiceDiscrepancyItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String productSource;
  final String category;
  final String tag;
  final double unitCost;
  final double sellingPrice;
  final int orderedQuantity;
  final int invoicedQuantity;
  final PoDiscrepancyType type;
  final String rawDocText;

  PoInvoiceDiscrepancyItem({
    required this.productId,
    required this.productName,
    this.imageUrl = '',
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    required this.unitCost,
    this.sellingPrice = 0.0,
    required this.orderedQuantity,
    required this.invoicedQuantity,
    required this.type,
    this.rawDocText = '',
  });

  int get differenceQuantity => (invoicedQuantity - orderedQuantity).abs();
  double get orderedTotal => orderedQuantity * unitCost;
  double get invoicedTotal => invoicedQuantity * unitCost;
  double get costDifference => invoicedTotal - orderedTotal;
}
