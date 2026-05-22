import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../storage/inventory_repo.dart';
import '../utils/ingredient_normalizer.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

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

class InventoryNotifier extends Notifier<List<Ingredient>>
    with PersistenceQueue {
  late final InventoryRepo _repo;

  @override
  List<Ingredient> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _repo.loadAll();
  }

  Future<void> add(Ingredient item) async {
    final normalizedItem = normalizeIngredientCategory(item);
    final stampedItem =
        normalizedItem.addedAt == null
            ? normalizedItem.copyWith(addedAt: DateTime.now())
            : normalizedItem;
    final itemToAdd = refreshIngredientFreshness(stampedItem);
    final updated = [...state, itemToAdd];
    state = updated;
    return queuePersistence(() async {
      _repo.saveItems(updated);
      await _recordAddHistory(itemToAdd);
      ref.read(_addHistoryVersionProvider.notifier).state++;
    });
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state]..removeAt(index);
    state = updated;
    return queuePersistence(() async {
      _repo.saveItems(updated);
    });
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    updated.insert(clampedIndex, normalizeInventoryIngredient(item));
    state = updated;
    return queuePersistence(() async {
      _repo.saveItems(updated);
    });
  }

  Future<void> update(int index, Ingredient item) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    final normalizedItem = normalizeIngredientCategory(item);
    final stampedItem =
        normalizedItem.addedAt == null
            ? normalizedItem.copyWith(addedAt: state[index].addedAt)
            : normalizedItem;
    updated[index] = refreshIngredientFreshness(stampedItem);
    state = updated;
    return queuePersistence(() async {
      _repo.saveItems(updated);
    });
  }

  List<Ingredient> getByCategory(String category) {
    return inventoryItemsForCategory(state, category);
  }

  Future<void> _recordAddHistory(Ingredient item) async {
    final history = _repo.loadHistory();
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
    _repo.saveHistory(history);
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

final _addHistoryVersionProvider = StateProvider<int>((ref) => 0);

final expiringItemsProvider = Provider<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.where(isNotFreshIngredient).toList();
});

final recentAdditionsProvider = Provider<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.reversed.take(2).toList();
});

final statCountsProvider = Provider<({int total, int expiringSoon})>((ref) {
  final items = ref.watch(inventoryProvider);
  final expiringSoon = notFreshIngredientCount(items);
  return (total: items.length, expiringSoon: expiringSoon);
});

final categoriesProvider = Provider<List<String>>((ref) {
  return const [inventoryFilterAll, ...FoodCategories.values];
});

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

final selectedCategoryProvider = StateProvider<String>(
  (ref) => inventoryFilterAll,
);

final filteredByCategoryProvider = Provider<List<Ingredient>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final items = ref.watch(inventoryProvider);
  return inventoryItemsForCategory(items, category);
});

final frequentItemsProvider = Provider<List<FrequentItem>>((ref) {
  ref.watch(_addHistoryVersionProvider);
  final repo = ref.read(inventoryRepoProvider);
  final history = repo.loadHistory();
  if (history.isEmpty) return [];

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

  items.sort((a, b) => b.count.compareTo(a.count));
  return items.where((i) => i.count >= 2).take(6).toList();
});
