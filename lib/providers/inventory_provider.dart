import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../storage/inventory_repo.dart';
import '../utils/ingredient_normalizer.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

export 'storage_service_provider.dart' show inventorySeedProvider;

const inventoryItemsStorageKey = 'inventory_items';
const addHistoryStorageKey = 'add_history';
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

  Future<void> _save(List<Ingredient> items) async {
    _repo.saveItems(items);
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
      await _save(updated);
      await ref.read(_addHistoryProvider.notifier).record(itemToAdd);
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
    updated.insert(clampedIndex, normalizeInventoryIngredient(item));
    state = updated;
    return queuePersistence(() => _save(updated));
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
    return queuePersistence(() => _save(updated));
  }

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
          current = [...current]
            ..[index] = refreshIngredientFreshness(
              existing.copyWith(quantity: summed),
            );
      }
    }
    state = current;
    return queuePersistence(() => _save(current));
  }

  Future<void> applyDeductionProposals(
    List<DeductionProposal> proposals,
  ) async {
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
        final newQty =
            remaining == remaining.roundToDouble()
                ? remaining.toInt().toString()
                : remaining.toString();
        current[i] = refreshIngredientFreshness(
          existing.copyWith(quantity: newQty),
        );
      }
    }
    if (removalIndices.isNotEmpty) {
      final sortedDesc =
          removalIndices.toList()..sort((a, b) => b.compareTo(a));
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
    return refreshIngredientFreshness(
      normalizeIngredientCategory(
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
    final mergedTarget = refreshIngredientFreshness(
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
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

class _AddHistoryNotifier extends Notifier<List<FrequentItem>> {
  late final InventoryRepo _repo;

  @override
  List<FrequentItem> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _itemsFromHistoryMap(_repo.loadHistory());
  }

  Future<void> record(Ingredient item) async {
    final history = Map<String, dynamic>.from(_repo.loadHistory());
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
    state = _itemsFromHistoryMap(history);
  }

  List<FrequentItem> _itemsFromHistoryMap(Map<String, dynamic> history) {
    return history.entries.map((e) {
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
  }
}

final _addHistoryProvider =
    NotifierProvider<_AddHistoryNotifier, List<FrequentItem>>(
      _AddHistoryNotifier.new,
    );

final expiringItemsProvider = Provider.autoDispose<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.where(isNotFreshIngredient).toList();
});

final recentAdditionsProvider = Provider.autoDispose<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.reversed.take(2).toList();
});

final statCountsProvider =
    Provider.autoDispose<({int total, int expiringSoon})>((ref) {
      final items = ref.watch(inventoryProvider);
      final expiringSoon = notFreshIngredientCount(items);
      return (total: items.length, expiringSoon: expiringSoon);
    });

final categoriesProvider = Provider.autoDispose<List<String>>((ref) {
  return const [inventoryFilterAll, ...FoodCategories.values];
});

final storageAreasProvider = Provider.autoDispose<List<StorageArea>>((ref) {
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

final filteredByCategoryProvider = Provider.autoDispose<List<Ingredient>>((
  ref,
) {
  final category = ref.watch(selectedCategoryProvider);
  final items = ref.watch(inventoryProvider);
  return inventoryItemsForCategory(items, category);
});

final inventorySearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

final filteredInventoryItemsProvider = Provider.autoDispose<List<Ingredient>>((
  ref,
) {
  final query = ref.watch(inventorySearchQueryProvider).trim().toLowerCase();
  final items = ref.watch(filteredByCategoryProvider);
  if (query.isEmpty) return items;
  return items
      .where((item) => item.name.toLowerCase().contains(query))
      .toList();
});

final frequentItemsProvider = Provider.autoDispose<List<FrequentItem>>((ref) {
  final all = [...ref.watch(_addHistoryProvider)];
  all.sort((a, b) => b.count.compareTo(a.count));
  return all.where((i) => i.count >= 2).take(6).toList();
});

final lowStockItemsProvider = Provider.autoDispose<List<FrequentItem>>((ref) {
  final all = ref.watch(_addHistoryProvider);
  final inventory = ref.watch(inventoryProvider);
  final presentNames =
      inventory.map((i) => i.name.trim().toLowerCase()).toSet();

  final filtered =
      all
          .where((f) => f.count >= 3)
          .where((f) => !presentNames.contains(f.name.trim().toLowerCase()))
          .toList();
  filtered.sort((a, b) => b.count.compareTo(a.count));
  return filtered;
});
