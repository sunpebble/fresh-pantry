import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../data/food_knowledge.dart';
import '../storage/shopping_item_normalizer.dart';
import '../storage/shopping_repo.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_ids.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

export 'storage_service_provider.dart' show shoppingSeedProvider;

const shoppingItemsStorageKey = 'shopping_items';
const _syncOperationIds = Uuid();

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
    final filtered = items
        .where(
          (item) =>
              filter == ShoppingFilter.todo ? !item.isChecked : item.isChecked,
        )
        .toList();
    if (filtered.isNotEmpty) {
      result[category] = filtered;
    }
  });
  return result;
}

class ShoppingNotifier extends Notifier<List<ShoppingItem>>
    with PersistenceQueue {
  late ShoppingRepo _repo;

  @override
  List<ShoppingItem> build() {
    _repo = ref.read(shoppingRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _save(List<ShoppingItem> items) async {
    _repo.saveItems(items);
  }

  Future<void> _enqueueSync({
    required SyncEntityType entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> patch,
    int? baseVersion,
  }) {
    final householdId = ref.read(selectedHouseholdIdProvider).trim();
    if (householdId.isEmpty || entityId.trim().isEmpty) {
      return Future.value();
    }

    return ref
        .read(syncOutboxRepoProvider)
        .enqueue(
          SyncOperation(
            id: _syncOperationIds.v4(),
            householdId: householdId,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            patch: patch,
            baseVersion: baseVersion,
            clientId: ref.read(syncClientIdProvider),
            createdAt: DateTime.now().toUtc(),
          ),
        )
        .then((_) => unawaited(ref.read(syncPushPendingProvider)()));
  }

  ShoppingItem _withSyncId(ShoppingItem item) {
    final householdId = ref.read(selectedHouseholdIdProvider).trim();
    if (householdId.isEmpty || isUuid(item.id)) return item;
    return item.copyWith(id: newSyncEntityId());
  }

  Future<void> replaceFromRemote(List<ShoppingItem> items) async {
    // Dedup by id (same identity rule the repo applies on load) so the
    // in-memory list cannot diverge from the persisted/reloaded list.
    final normalized = deduplicateShoppingItems(
      items.map(normalizeShoppingItem),
    );
    state = normalized;
    await queuePersistence(() => _save(normalized));
  }

  Future<bool> add(ShoppingItem item) async {
    final normalizedItem = withUniqueShoppingItemId(
      normalizeShoppingItem(_withSyncId(item)),
      state.map((item) => item.id).toSet(),
    );
    final nameKey = shoppingItemNameKey(normalizedItem.name);
    if (nameKey.isEmpty ||
        state.any((item) => shoppingItemNameKey(item.name) == nameKey)) {
      return false;
    }

    final prior = state;
    final updated = [...state, normalizedItem];
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSync(
      entityType: SyncEntityType.shoppingItem,
      entityId: normalizedItem.id,
      operation: SyncOperationType.create,
      patch: normalizedItem.toJson(),
    );
    return true;
  }

  Future<void> remove(String id) async {
    final removedIndex = state.indexWhere((item) => item.id == id);
    final removed = removedIndex == -1 ? null : state[removedIndex];
    final updated = state.where((item) => item.id != id).toList();
    if (updated.length == state.length) {
      return;
    }

    final prior = state;
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    final deletedAt = DateTime.now().toUtc();
    await _enqueueSync(
      entityType: SyncEntityType.shoppingItem,
      entityId: id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: removed?.remoteVersion,
    );
  }

  Future<void> toggleCheck(String id) async {
    var changed = false;
    ShoppingItem? original;
    ShoppingItem? toggled;
    final updated = state.map((item) {
      if (item.id == id) {
        changed = true;
        original = item;
        toggled = item.copyWith(isChecked: !item.isChecked);
        return toggled!;
      }
      return item;
    }).toList();
    if (!changed) {
      return;
    }

    final prior = state;
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSync(
      entityType: SyncEntityType.shoppingItem,
      entityId: id,
      operation: SyncOperationType.toggleChecked,
      patch: {'isChecked': toggled!.isChecked},
      baseVersion: original?.remoteVersion,
    );
  }

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

final groupedShoppingProvider = Provider<Map<String, List<ShoppingItem>>>((
  ref,
) {
  final items = ref.watch(shoppingProvider);
  return groupShoppingItems(items);
});

final checkedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return shoppingCountsFor(items).checked;
});

final uncheckedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return shoppingCountsFor(items).unchecked;
});
