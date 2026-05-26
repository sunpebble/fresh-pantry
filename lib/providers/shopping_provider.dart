import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../utils/json_object_list.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

const shoppingItemsStorageKey = 'shopping_items';

enum ShoppingFilter { all, todo, done }

class ShoppingListViewState {
  const ShoppingListViewState({
    required this.items,
    required this.groupedItems,
    required this.visibleGroups,
    required this.filter,
    required this.checkedCount,
    required this.uncheckedCount,
  });

  final List<ShoppingItem> items;
  final Map<String, List<ShoppingItem>> groupedItems;
  final Map<String, List<ShoppingItem>> visibleGroups;
  final ShoppingFilter filter;
  final int checkedCount;
  final int uncheckedCount;

  int get total => items.length;
  double get progress => total == 0 ? 0.0 : checkedCount / total;
}

ShoppingItem _normalizeShoppingItemCategory(ShoppingItem item) {
  final category =
      FoodCategories.normalize(item.category) ?? FoodCategories.other;
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

String _shoppingItemNameKey(String name) => name.trim().toLowerCase();

({int checked, int unchecked}) shoppingCountsFor(Iterable<ShoppingItem> items) {
  var checked = 0;
  var unchecked = 0;
  for (final item in items) {
    if (item.isChecked) {
      checked += 1;
    } else {
      unchecked += 1;
    }
  }
  return (checked: checked, unchecked: unchecked);
}

Map<String, List<ShoppingItem>> groupShoppingItems(
  Iterable<ShoppingItem> items,
) {
  final grouped = <String, List<ShoppingItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.category, () => []).add(item);
  }
  return grouped;
}

Map<String, List<ShoppingItem>> filterShoppingGroups(
  Map<String, List<ShoppingItem>> grouped,
  ShoppingFilter filter,
) {
  if (filter == ShoppingFilter.all) return grouped;

  final result = <String, List<ShoppingItem>>{};
  grouped.forEach((category, items) {
    final filtered =
        items
            .where(
              (item) =>
                  filter == ShoppingFilter.todo
                      ? !item.isChecked
                      : item.isChecked,
            )
            .toList();
    if (filtered.isNotEmpty) {
      result[category] = filtered;
    }
  });
  return result;
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

/// Shopping list state with local persistence
class ShoppingNotifier extends Notifier<List<ShoppingItem>>
    with PersistenceQueue {
  late final SharedPreferences _prefs;

  @override
  List<ShoppingItem> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return ref.read(shoppingSeedProvider);
  }

  Future<void> _save(List<ShoppingItem> items) async {
    final jsonString = json.encode(items.map((e) => e.toJson()).toList());
    final saved = await _prefs.setString(shoppingItemsStorageKey, jsonString);
    if (!saved) {
      throw StateError('Failed to save shopping items');
    }
  }

  Future<bool> add(ShoppingItem item) async {
    final normalizedItem = _withUniqueShoppingItemId(
      _normalizeShoppingItemCategory(item),
      state.map((item) => item.id).toSet(),
    );
    final nameKey = _shoppingItemNameKey(normalizedItem.name);
    if (nameKey.isEmpty ||
        state.any((item) => _shoppingItemNameKey(item.name) == nameKey)) {
      return false;
    }

    final updated = [...state, normalizedItem];
    state = updated;
    await queuePersistence(() => _save(updated));
    return true;
  }

  Future<void> remove(String id) async {
    final updated = state.where((item) => item.id != id).toList();
    if (updated.length == state.length) {
      return;
    }

    state = updated;
    await queuePersistence(() => _save(updated));
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
    await queuePersistence(() => _save(updated));
  }

  /// Build a ShoppingItem from the given inventory item and add it.
  /// Returns true if added, false if a duplicate name was found.
  Future<bool> addFromIngredient(Ingredient ingredient) {
    return add(ShoppingItem.fromIngredient(ingredient));
  }

  Future<bool> addFromSuggestion(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;

    final newItem = ShoppingItem(
      id: ShoppingItem.newId(),
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

final shoppingFilterProvider = StateProvider<ShoppingFilter>(
  (ref) => ShoppingFilter.all,
);

final collapsedShoppingCategoriesProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);

final shoppingListViewProvider = Provider<ShoppingListViewState>((ref) {
  final items = ref.watch(shoppingProvider);
  final filter = ref.watch(shoppingFilterProvider);
  final groupedItems = groupShoppingItems(items);
  final counts = shoppingCountsFor(items);
  return ShoppingListViewState(
    items: items,
    groupedItems: groupedItems,
    visibleGroups: filterShoppingGroups(groupedItems, filter),
    filter: filter,
    checkedCount: counts.checked,
    uncheckedCount: counts.unchecked,
  );
});

/// 启动时预 hydrated 的 shopping 种子,由 main.dart 预解码后通过 override 注入。
///
/// Fallback: 未被 override 时回退到 prefs 同步解码,保持升级前行为。
final shoppingSeedProvider = Provider<List<ShoppingItem>>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return loadShoppingFromPrefs(prefs);
});

/// 把存储中的 shopping JSON 解码为 `List<ShoppingItem>`(同步)。
/// 仅供 main.dart hydrate 与 [shoppingSeedProvider] fallback 使用。
List<ShoppingItem> loadShoppingFromPrefs(SharedPreferences prefs) {
  final jsonString = prefs.getString(shoppingItemsStorageKey);
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

/// Shopping items grouped by category
final groupedShoppingProvider = Provider<Map<String, List<ShoppingItem>>>((
  ref,
) {
  final items = ref.watch(shoppingProvider);
  return groupShoppingItems(items);
});

/// Count of checked items
final checkedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return shoppingCountsFor(items).checked;
});

/// Count of unchecked items
final uncheckedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return shoppingCountsFor(items).unchecked;
});
