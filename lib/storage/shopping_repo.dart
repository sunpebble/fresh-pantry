import 'dart:convert';
import '../data/food_categories.dart';
import '../models/shopping_item.dart';
import '../utils/json_object_list.dart';
import 'storage_adapter.dart';

class ShoppingRepo {
  static const _shoppingKey = 'shopping_items';

  final StorageAdapter _adapter;
  List<ShoppingItem>? _hydratedSeed;

  ShoppingRepo(this._adapter);

  void hydrate(List<ShoppingItem> seed) {
    _hydratedSeed = seed;
  }

  List<ShoppingItem> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final json = _adapter.read(_shoppingKey);
    if (json == null) return [];
    try {
      final items =
          decodeJsonObjectList(json)
              .map(ShoppingItem.fromJson)
              .map(_normalizeShoppingItemCategory);
      return _deduplicateShoppingItems(items);
    } catch (_) {
      return [];
    }
  }

  void saveItems(List<ShoppingItem> items) {
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    _adapter.write(_shoppingKey, jsonStr);
  }

  ShoppingItem _normalizeShoppingItemCategory(ShoppingItem item) {
    final category =
        FoodCategories.normalize(item.category) ?? FoodCategories.other;
    if (category == item.category) return item;
    return item.copyWith(category: category);
  }

  String _shoppingItemNameKey(String name) => name.trim().toLowerCase();

  ShoppingItem _withUniqueShoppingItemId(
    ShoppingItem item,
    Set<String> existingIds,
  ) {
    final trimmedId = item.id.trim();
    final baseId = trimmedId.isEmpty ? ShoppingItem.newId() : trimmedId;
    var candidateId = baseId;
    var suffix = 2;

    while (existingIds.contains(candidateId)) {
      candidateId = '${baseId}_$suffix';
      suffix += 1;
    }

    existingIds.add(candidateId);
    return candidateId == item.id ? item : item.copyWith(id: candidateId);
  }

  List<ShoppingItem> _deduplicateShoppingItems(Iterable<ShoppingItem> items) {
    final seenNames = <String>{};
    final seenIds = <String>{};
    final deduplicated = <ShoppingItem>[];

    for (final item in items) {
      final nameKey = _shoppingItemNameKey(item.name);
      if (nameKey.isEmpty || seenNames.contains(nameKey)) continue;
      seenNames.add(nameKey);
      deduplicated.add(_withUniqueShoppingItemId(item, seenIds));
    }

    return deduplicated;
  }
}
