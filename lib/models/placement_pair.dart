/// Model representing a configured pairing between two placement products/SKUs.
///
/// When either product in a pair is placed (delivered to a store),
/// both products are marked as placed for that store's monthly placement target.
class PlacementPair {
  final String product1;
  final String product2;

  const PlacementPair({
    required this.product1,
    required this.product2,
  });

  /// Checks if the given [productName] matches either item in this pair (case-insensitive).
  bool matches(String productName) {
    final lower = productName.trim().toLowerCase();
    return product1.trim().toLowerCase() == lower || product2.trim().toLowerCase() == lower;
  }

  /// Returns the other paired product name if [productName] matches one of the items.
  String? getOther(String productName) {
    final lower = productName.trim().toLowerCase();
    if (product1.trim().toLowerCase() == lower) return product2;
    if (product2.trim().toLowerCase() == lower) return product1;
    return null;
  }

  factory PlacementPair.fromJson(Map<String, Object?> json) {
    return PlacementPair(
      product1: (json['product1'] as String? ?? '').trim(),
      product2: (json['product2'] as String? ?? '').trim(),
    );
  }

  Map<String, String> toJson() {
    return {
      'product1': product1,
      'product2': product2,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacementPair &&
          ((product1.trim().toLowerCase() == other.product1.trim().toLowerCase() &&
                  product2.trim().toLowerCase() == other.product2.trim().toLowerCase()) ||
              (product1.trim().toLowerCase() == other.product2.trim().toLowerCase() &&
                  product2.trim().toLowerCase() == other.product1.trim().toLowerCase()));

  @override
  int get hashCode => product1.trim().toLowerCase().hashCode ^ product2.trim().toLowerCase().hashCode;

  @override
  String toString() => 'PlacementPair($product1 <-> $product2)';
}
