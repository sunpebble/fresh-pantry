import 'dart:convert';
import '../models/ingredient.dart';
import '../utils/ingredient_normalizer.dart';
import '../utils/json_object_list.dart';
import 'storage_adapter.dart';

class InventoryRepo {
  static const _inventoryKey = 'inventory_items';
  static const _addHistoryKey = 'add_history';

  final StorageAdapter _adapter;
  List<Ingredient>? _hydratedSeed;

  InventoryRepo(this._adapter);

  void hydrate(List<Ingredient> seed) {
    _hydratedSeed = seed;
  }

  List<Ingredient> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final jsonStr = _adapter.read(_inventoryKey);
    if (jsonStr == null) return [];
    try {
      return decodeJsonObjectList(jsonStr)
          .map(Ingredient.fromJson)
          .map(normalizeInventoryIngredient)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveItems(List<Ingredient> items) {
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    _adapter.write(_inventoryKey, jsonStr);
  }

  Map<String, dynamic> loadHistory() {
    final jsonStr = _adapter.read(_addHistoryKey);
    if (jsonStr == null) return {};
    try {
      return json.decode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void saveHistory(Map<String, dynamic> history) {
    _adapter.write(_addHistoryKey, json.encode(history));
  }

  void clearHistory() {
    _adapter.write(_addHistoryKey, json.encode(<String, dynamic>{}));
  }
}
