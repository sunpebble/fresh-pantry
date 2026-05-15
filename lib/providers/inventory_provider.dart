import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../utils/expiry_calculator.dart';
import '../utils/json_object_list.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

const kInventoryKey = 'inventory_items';
const kAddHistoryKey = 'add_history';
const inventoryFilterAll = '全部';
const inventoryFilterNotFresh = '不新鲜';

bool isNotFreshIngredient(Ingredient item) {
  return item.state == FreshnessState.expiringSoon ||
      item.state == FreshnessState.expired;
}

int inventoryIndexOf(List<Ingredient> items, Ingredient item) {
  final identityIndex = items.indexWhere(
    (candidate) => identical(candidate, item),
  );
  if (identityIndex != -1) return identityIndex;
  return items.indexOf(item);
}

List<Ingredient> inventoryItemsForCategory(
  List<Ingredient> items,
  String category,
) {
  if (category == inventoryFilterAll || category.isEmpty) return items;
  if (category == inventoryFilterNotFresh) {
    return items.where(isNotFreshIngredient).toList();
  }

  final normalizedCategory = FoodCategories.normalize(category);
  return items
      .where(
        (item) => FoodCategories.normalize(item.category) == normalizedCategory,
      )
      .toList();
}

int notFreshIngredientCount(Iterable<Ingredient> items) {
  return items.where(isNotFreshIngredient).length;
}

Ingredient _normalizeIngredientCategory(Ingredient item) {
  final category = FoodCategories.normalize(item.category);
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

int? _shelfLifeDaysFor(Ingredient item) {
  final expiryDate = item.expiryDate;
  if (expiryDate == null) return null;

  final savedShelfLifeDays = item.shelfLifeDays;
  if (savedShelfLifeDays != null && savedShelfLifeDays > 0) {
    return savedShelfLifeDays;
  }

  final defaultShelfLifeDays = FoodKnowledge.lookup(item.name)?.shelfLifeDays;
  if (defaultShelfLifeDays != null && defaultShelfLifeDays > 0) {
    return defaultShelfLifeDays;
  }

  if (item.addedAt == null) return null;

  final days = calendarDaysBetween(item.addedAt!, expiryDate);
  return days > 0 ? days : null;
}

Ingredient _refreshIngredientFreshness(Ingredient item, {DateTime? now}) {
  final expiryDate = item.expiryDate;
  if (expiryDate == null) return item;

  final shelfLifeDays = _shelfLifeDaysFor(item);
  if (shelfLifeDays == null) {
    return item.copyWith(expiryLabel: expiryLabelFor(expiryDate, now: now));
  }

  final freshness = expiryFreshness(
    expiryDate: expiryDate,
    totalShelfLifeDays: shelfLifeDays,
    now: now,
  );

  return item.copyWith(
    freshnessPercent: freshness,
    state: freshnessStateForExpiry(
      freshness: freshness,
      expiryDate: expiryDate,
      now: now,
    ),
    expiryLabel: expiryLabelFor(expiryDate, now: now),
  );
}

Ingredient _normalizeInventoryIngredient(Ingredient item) {
  return _refreshIngredientFreshness(_normalizeIngredientCategory(item));
}

/// Inventory state (CRUD) with local persistence
class InventoryNotifier extends Notifier<List<Ingredient>>
    with PersistenceQueue {
  late final SharedPreferences _prefs;

  @override
  List<Ingredient> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return ref.read(inventorySeedProvider);
  }

  Future<void> _save(List<Ingredient> items) async {
    final jsonString = json.encode(items.map((e) => e.toJson()).toList());
    final saved = await _prefs.setString(kInventoryKey, jsonString);
    if (!saved) {
      throw StateError('Failed to save inventory items');
    }
  }

  Future<void> add(Ingredient item) async {
    final normalizedItem = _normalizeIngredientCategory(item);
    final stampedItem =
        normalizedItem.addedAt == null
            ? normalizedItem.copyWith(addedAt: DateTime.now())
            : normalizedItem;
    final itemToAdd = _refreshIngredientFreshness(stampedItem);
    final updated = [...state, itemToAdd];
    state = updated;
    return queuePersistence(() async {
      await _save(updated);
      await _recordAddHistory(itemToAdd);
      ref.read(_addHistoryVersionProvider.notifier).state++;
    });
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state]..removeAt(index);
    state = updated;
    return queuePersistence(() => _save(updated));
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    updated.insert(clampedIndex, _normalizeInventoryIngredient(item));
    state = updated;
    return queuePersistence(() => _save(updated));
  }

  Future<void> update(int index, Ingredient item) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    final normalizedItem = _normalizeIngredientCategory(item);
    final stampedItem =
        normalizedItem.addedAt == null
            ? normalizedItem.copyWith(addedAt: state[index].addedAt)
            : normalizedItem;
    updated[index] = _refreshIngredientFreshness(stampedItem);
    state = updated;
    return queuePersistence(() => _save(updated));
  }

  /// Applies a list of IntakeProposals atomically: newRow proposals append,
  /// mergeInto proposals add quantity to the referenced row. Unselected
  /// proposals are ignored.
  Future<void> applyIntakeProposals(List<IntakeProposal> proposals) async {
    var current = [...state];
    for (final p in proposals) {
      if (!p.selected) continue;
      switch (p.action) {
        case IntakeAction.newRow:
          current = [...current, _ingredientFromProposal(p)];
        case IntakeAction.mergeInto:
          final index = int.tryParse(p.mergeTargetId ?? '');
          if (index == null || index < 0 || index >= current.length) {
            current = [...current, _ingredientFromProposal(p)];
            break;
          }
          final existing = current[index];
          final summed = _sumQuantity(existing.quantity, p.quantity);
          current = [...current]..[index] = _refreshIngredientFreshness(
                existing.copyWith(quantity: summed),
              );
      }
    }
    state = current;
    return queuePersistence(() => _save(current));
  }

  /// Applies a list of DeductionProposals atomically. Each Proposal references
  /// an inventory row by index; deducted quantities reaching 0 (or negative)
  /// remove the row.
  Future<void> applyDeductionProposals(List<DeductionProposal> proposals) async {
    final removalIndices = <int>{};
    var current = [...state];
    for (final p in proposals) {
      if (!p.selected) continue;
      if (p.action == DeductionAction.skip) continue;
      final i = p.chosenIndex;
      if (i < 0 || i >= current.length) continue;
      final existing = current[i];
      final remaining = _subtractQuantity(existing.quantity, p.deductAmount);
      if (remaining <= 0) {
        removalIndices.add(i);
      } else {
        final newQty = remaining == remaining.roundToDouble()
            ? remaining.toInt().toString()
            : remaining.toString();
        current[i] = _refreshIngredientFreshness(
          existing.copyWith(quantity: newQty),
        );
      }
    }
    if (removalIndices.isNotEmpty) {
      final sortedDesc = removalIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in sortedDesc) {
        current.removeAt(idx);
      }
    }
    state = List<Ingredient>.from(current);
    return queuePersistence(() => _save(state));
  }

  double _subtractQuantity(String existing, String deduct) {
    final ne = double.tryParse(existing) ?? 0;
    final nd = double.tryParse(deduct) ?? 0;
    return ne - nd;
  }

  Ingredient _ingredientFromProposal(IntakeProposal p) {
    final shelf = p.shelfLifeDays;
    final addedAt = DateTime.now();
    final expiryDate =
        shelf == null ? null : addedAt.add(Duration(days: shelf));
    return _refreshIngredientFreshness(
      _normalizeIngredientCategory(
        Ingredient(
          name: p.name,
          quantity: p.quantity,
          unit: p.unit,
          imageUrl: '',
          freshnessPercent: 1.0,
          state: FreshnessState.fresh,
          category: p.category,
          storage: p.storage,
          expiryDate: expiryDate,
          addedAt: addedAt,
          shelfLifeDays: shelf,
        ),
      ),
    );
  }

  String _sumQuantity(String a, String b) {
    final na = double.tryParse(a) ?? 0;
    final nb = double.tryParse(b) ?? 0;
    final sum = na + nb;
    if (sum == sum.roundToDouble()) return sum.toInt().toString();
    return sum.toString();
  }

  /// Merges two inventory rows (`sourceIndex` into `targetIndex`):
  /// quantities sum, expiry takes the earlier of the two (so urgency signal
  /// is preserved), source row is removed.
  Future<void> mergeBatch(int sourceIndex, int targetIndex) async {
    if (sourceIndex == targetIndex) return;
    if (sourceIndex < 0 || sourceIndex >= state.length) return;
    if (targetIndex < 0 || targetIndex >= state.length) return;
    final source = state[sourceIndex];
    final target = state[targetIndex];
    if (source.unit.trim() != target.unit.trim()) return;
    if (source.storage != target.storage) return;
    final summed = _sumQuantity(source.quantity, target.quantity);
    final earlierExpiry = _earlierExpiry(source.expiryDate, target.expiryDate);
    final mergedTarget = _refreshIngredientFreshness(
      target.copyWith(quantity: summed, expiryDate: earlierExpiry),
    );
    final updated = [...state];
    updated[targetIndex] = mergedTarget;
    updated.removeAt(sourceIndex);
    state = updated;
    return queuePersistence(() => _save(updated));
  }

  DateTime? _earlierExpiry(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  List<Ingredient> getByCategory(String category) {
    return inventoryItemsForCategory(state, category);
  }

  Future<void> _recordAddHistory(Ingredient item) async {
    final historyJson = _prefs.getString(kAddHistoryKey);
    final history = <String, dynamic>{};
    if (historyJson != null) {
      try {
        history.addAll((json.decode(historyJson) as Map<String, dynamic>));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error decoding add history: $e');
        }
      }
    }

    final key = item.name;
    final existing = history[key];
    final existingCount = switch (existing) {
      {'count': final num count} => count.toInt(),
      num count => count.toInt(),
      _ => 0,
    };
    history[key] = {
      'count': existingCount + 1,
      'category': FoodCategories.normalize(item.category) ?? '',
      'storage': item.storage.name,
      'unit': item.unit,
    };

    final saved = await _prefs.setString(kAddHistoryKey, json.encode(history));
    if (!saved) {
      throw StateError('Failed to save add history');
    }
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

/// 启动时预 hydrated 的 inventory 种子，由 main.dart 预解码后通过 override 注入。
/// Notifier.build 直接同步读取，从而把 prefs 解码移出首帧关键路径。
///
/// Fallback: 当未被 override 时读取 prefs 中的 JSON。若 key 不存在则返回空列表
/// (main.dart 始终注入实际数据，包括 kDebugMode 下的 mock 数据)。
final inventorySeedProvider = Provider<List<Ingredient>>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  final jsonString = prefs.getString(kInventoryKey);
  if (jsonString == null) return [];
  try {
    return decodeJsonObjectList(jsonString)
        .map(Ingredient.fromJson)
        .map(_normalizeInventoryIngredient)
        .toList();
  } catch (_) {
    return [];
  }
});

/// 把存储中的 inventory JSON 解码为 `List<Ingredient>`(同步)。
/// 仅供 main.dart hydrate 与 [inventorySeedProvider] fallback 使用,公共 API 不依赖。
List<Ingredient> loadInventoryFromPrefs(SharedPreferences prefs) {
  final jsonString = prefs.getString(kInventoryKey);
  if (jsonString == null) {
    return kDebugMode ? List.from(MockData.inventoryItems) : [];
  }
  try {
    return decodeJsonObjectList(
      jsonString,
    ).map(Ingredient.fromJson).map(_normalizeInventoryIngredient).toList();
  } catch (_) {
    return kDebugMode ? List.from(MockData.inventoryItems) : [];
  }
}

final _addHistoryVersionProvider = StateProvider<int>((ref) => 0);

/// Items expiring soon (state == expiringSoon or expired)
final expiringItemsProvider = Provider<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.where(isNotFreshIngredient).toList();
});

/// Recent additions from the current inventory, newest first.
final recentAdditionsProvider = Provider<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.reversed.take(2).toList();
});

/// Stat counts for dashboard
final statCountsProvider = Provider<({int total, int expiringSoon})>((ref) {
  final items = ref.watch(inventoryProvider);
  final expiringSoon = notFreshIngredientCount(items);
  return (total: items.length, expiringSoon: expiringSoon);
});

/// Fixed category filters for inventory.
final categoriesProvider = Provider<List<String>>((ref) {
  return const [inventoryFilterAll, ...FoodCategories.values];
});

/// Storage area stats derived from actual inventory
final storageAreasProvider = Provider<List<StorageArea>>((ref) {
  final items = ref.watch(inventoryProvider);
  const maxCapacity = {IconType.fridge: 20, IconType.pantry: 50};
  const names = {IconType.fridge: '冰箱', IconType.pantry: '食品柜'};
  final counts = {for (final type in IconType.values) type: 0};

  for (final item in items) {
    counts[item.storage] = (counts[item.storage] ?? 0) + 1;
  }

  return IconType.values.map((type) {
    final count = counts[type] ?? 0;
    final cap = maxCapacity[type]!;
    return StorageArea(
      name: names[type]!,
      icon: type,
      itemCount: count,
      capacityPercent: (count / cap).clamp(0.0, 1.0),
    );
  }).toList();
});

/// Currently selected category filter
final selectedCategoryProvider = StateProvider<String>(
  (ref) => inventoryFilterAll,
);

/// Inventory filtered by selected category
final filteredByCategoryProvider = Provider<List<Ingredient>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final items = ref.watch(inventoryProvider);
  return inventoryItemsForCategory(items, category);
});

/// Top frequent items derived from add history.
final frequentItemsProvider = Provider<List<FrequentItem>>((ref) {
  // Re-read after add history changes.
  ref.watch(_addHistoryVersionProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  final historyJson = prefs.getString(kAddHistoryKey);
  if (historyJson == null) return [];

  try {
    final history = json.decode(historyJson) as Map<String, dynamic>;
    final items =
        history.entries.map((e) {
          final value = e.value;
          final data = value is Map<String, dynamic> ? value : const {};
          final count = switch (value) {
            {'count': final num count} => count.toInt(),
            num count => count.toInt(),
            _ => 1,
          };
          final category = data['category'];
          final storageValue = data['storage'];
          final unit = data['unit'];
          final storageName = storageValue is String ? storageValue : 'fridge';
          final defaults = FoodKnowledge.lookup(e.key);

          final storage = iconTypeFromName(storageName);

          final rememberedCategory =
              category is String ? category : defaults?.category;

          return FrequentItem(
            name: e.key,
            category: FoodCategories.dropdownValue(rememberedCategory),
            storage: storage,
            unit: unit is String ? unit : '个',
            shelfLifeDays: defaults?.shelfLifeDays,
            count: count,
          );
        }).toList();

    // Sort by frequency, take top 6
    items.sort((a, b) => b.count.compareTo(a.count));
    return items.where((i) => i.count >= 2).take(6).toList();
  } catch (_) {
    return [];
  }
});
