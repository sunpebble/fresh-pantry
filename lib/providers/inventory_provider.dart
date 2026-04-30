import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../data/mock_data.dart';
import '../utils/expiry_calculator.dart';
import '../utils/json_object_list.dart';
import 'storage_service_provider.dart';

const _kInventoryKey = 'inventory_items';
const _kAddHistoryKey = 'add_history';
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

String expiryLabelFor(DateTime expiryDate, {DateTime? now}) {
  final days = daysUntilExpiry(expiryDate, now: now);
  if (days < 0) return '已过期${-days}天';
  if (days == 0) return '今天过期';
  if (days == 1) return '明天过期';
  return '$days天后过期';
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
class InventoryNotifier extends Notifier<List<Ingredient>> {
  late final SharedPreferences _prefs;
  Future<void> _pendingPersistence = Future.value();

  @override
  List<Ingredient> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<Ingredient> _load() {
    final jsonString = _prefs.getString(_kInventoryKey);
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

  Future<void> _save(List<Ingredient> items) async {
    final jsonString = json.encode(items.map((e) => e.toJson()).toList());
    final saved = await _prefs.setString(_kInventoryKey, jsonString);
    if (!saved) {
      throw StateError('Failed to save inventory items');
    }
  }

  Future<void> _queuePersistence(Future<void> Function() persist) {
    final next = _pendingPersistence.then((_) => persist());
    _pendingPersistence = next.catchError((_) {});
    return next;
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
    return _queuePersistence(() async {
      await _save(updated);
      await _recordAddHistory(itemToAdd);
      ref.read(_addHistoryVersionProvider.notifier).state++;
    });
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state]..removeAt(index);
    state = updated;
    return _queuePersistence(() => _save(updated));
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    updated.insert(clampedIndex, _normalizeInventoryIngredient(item));
    state = updated;
    return _queuePersistence(() => _save(updated));
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
    return _queuePersistence(() => _save(updated));
  }

  List<Ingredient> getByCategory(String category) {
    return inventoryItemsForCategory(state, category);
  }

  Future<void> _recordAddHistory(Ingredient item) async {
    final historyJson = _prefs.getString(_kAddHistoryKey);
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

    final saved = await _prefs.setString(_kAddHistoryKey, json.encode(history));
    if (!saved) {
      throw StateError('Failed to save add history');
    }
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

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

/// A frequently added item with remembered defaults.
class FrequentItem {
  final String name;
  final String category;
  final IconType storage;
  final String unit;
  final int? shelfLifeDays;
  final int count;

  const FrequentItem({
    required this.name,
    required this.category,
    required this.storage,
    required this.unit,
    this.shelfLifeDays,
    required this.count,
  });
}

/// Top frequent items derived from add history.
final frequentItemsProvider = Provider<List<FrequentItem>>((ref) {
  // Re-read after add history changes.
  ref.watch(_addHistoryVersionProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  final historyJson = prefs.getString(_kAddHistoryKey);
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
