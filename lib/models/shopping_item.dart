import 'ingredient.dart';

class ShoppingItem {
  final String id;
  final String name;
  final String detail;
  final String? imageUrl;
  final String category;
  final bool isChecked;

  const ShoppingItem({
    required this.id,
    required this.name,
    required this.detail,
    this.imageUrl,
    required this.category,
    this.isChecked = false,
  });

  /// Build a ShoppingItem from an Ingredient. Uses `id` if provided,
  /// otherwise generates a fresh one. Mirrors the existing `_shoppingItemFor`
  /// implementations in dashboard/inventory/ingredient_detail screens.
  factory ShoppingItem.fromIngredient(
    Ingredient ingredient, {
    String? id,
  }) {
    return ShoppingItem(
      id: id ?? 'si_${DateTime.now().millisecondsSinceEpoch}',
      name: ingredient.name,
      detail: '${ingredient.quantity} ${ingredient.unit}',
      imageUrl: ingredient.imageUrl.isEmpty ? null : ingredient.imageUrl,
      category: ingredient.category ?? '其他',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShoppingItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  ShoppingItem copyWith({
    String? id,
    String? name,
    String? detail,
    String? imageUrl,
    String? category,
    bool? isChecked,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'detail': detail,
      'imageUrl': imageUrl,
      'category': category,
      'isChecked': isChecked,
    };
  }

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String? ?? '其他',
      isChecked: json['isChecked'] as bool? ?? false,
    );
  }
}
