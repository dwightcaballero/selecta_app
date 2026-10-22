/// Model representing a dealer-defined sub-category for grouping and ordering products.
///
/// Sub-categories belong either to 'By Piece' or 'By Case' category.
class SubCategory {
  final String id;
  final String name;
  final String category; // 'By Piece' or 'By Case'
  final int order;
  final bool isActive;

  const SubCategory({
    required this.id,
    required this.name,
    required this.category,
    required this.order,
    this.isActive = true,
  });

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'By Piece',
      order: (json['order'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'order': order,
      'isActive': isActive,
    };
  }

  SubCategory copyWith({
    String? id,
    String? name,
    String? category,
    int? order,
    bool? isActive,
  }) {
    return SubCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      order: order ?? this.order,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubCategory &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          category == other.category &&
          order == other.order &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(id, name, category, order, isActive);

  @override
  String toString() => 'SubCategory($id, $name, $category, order: $order, active: $isActive)';
}
