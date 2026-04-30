import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shopping_item.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../utils/json_object_list.dart';
import 'storage_service_provider.dart';

const _kShoppingKey = 'shopping_items';

ShoppingItem _normalizeShoppingItemCategory(ShoppingItem item) {
  final category =
      FoodCategories.normalize(item.category) ?? FoodCategories.other;
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

String _shoppingItemNameKey(String name) => name.trim().toLowerCase();

List<ShoppingItem> _deduplicateShoppingItems(Iterable<ShoppingItem> items) {
  final seenNames = <String>{};
  final deduplicated = <ShoppingItem>[];

  for (final item in items) {
    final nameKey = _shoppingItemNameKey(item.name);
    if (nameKey.isEmpty || seenNames.contains(nameKey)) continue;
    seenNames.add(nameKey);
    deduplicated.add(item);
  }

  return deduplicated;
}

/// Shopping list state with local persistence
class ShoppingNotifier extends Notifier<List<ShoppingItem>> {
  late final SharedPreferences _prefs;
  Future<void> _pendingPersistence = Future.value();

  @override
  List<ShoppingItem> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<ShoppingItem> _load() {
    final jsonString = _prefs.getString(_kShoppingKey);
    if (jsonString == null) {
      return kDebugMode ? List.from(MockData.shoppingItems) : [];
    }
    try {
      final items = decodeJsonObjectList(
        jsonString,
      ).map(ShoppingItem.fromJson).map(_normalizeShoppingItemCategory);
      return _deduplicateShoppingItems(items);
    } catch (_) {
      return kDebugMode ? List.from(MockData.shoppingItems) : [];
    }
  }

  Future<void> _save(List<ShoppingItem> items) async {
    final jsonString = json.encode(items.map((e) => e.toJson()).toList());
    final saved = await _prefs.setString(_kShoppingKey, jsonString);
    if (!saved) {
      throw StateError('Failed to save shopping items');
    }
  }

  Future<void> _queueSave(List<ShoppingItem> items) {
    final next = _pendingPersistence.then((_) => _save(items));
    _pendingPersistence = next.catchError((_) {});
    return next;
  }

  Future<bool> add(ShoppingItem item) async {
    final normalizedItem = _normalizeShoppingItemCategory(item);
    final nameKey = _shoppingItemNameKey(normalizedItem.name);
    if (nameKey.isEmpty ||
        state.any((item) => _shoppingItemNameKey(item.name) == nameKey)) {
      return false;
    }

    final updated = [...state, normalizedItem];
    state = updated;
    await _queueSave(updated);
    return true;
  }

  Future<void> remove(String id) async {
    final updated = state.where((item) => item.id != id).toList();
    if (updated.length == state.length) {
      return;
    }

    state = updated;
    await _queueSave(updated);
  }

  Future<void> toggleCheck(String id) async {
    var changed = false;
    final updated =
        state.map((item) {
          if (item.id == id) {
            changed = true;
            return item.copyWith(isChecked: !item.isChecked);
          }
          return item;
        }).toList();
    if (!changed) {
      return;
    }

    state = updated;
    await _queueSave(updated);
  }

  Future<bool> addFromSuggestion(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;

    final newItem = ShoppingItem(
      id: 'si_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmedName,
      detail: '',
      category: FoodKnowledge.categoryFor(trimmedName),
    );
    return add(newItem);
  }
}

final shoppingProvider = NotifierProvider<ShoppingNotifier, List<ShoppingItem>>(
  ShoppingNotifier.new,
);

/// Shopping items grouped by category
final groupedShoppingProvider = Provider<Map<String, List<ShoppingItem>>>((
  ref,
) {
  final items = ref.watch(shoppingProvider);
  final grouped = <String, List<ShoppingItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.category, () => []).add(item);
  }
  return grouped;
});

/// Count of checked items
final checkedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => item.isChecked).length;
});

/// Count of unchecked items
final uncheckedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => !item.isChecked).length;
});
