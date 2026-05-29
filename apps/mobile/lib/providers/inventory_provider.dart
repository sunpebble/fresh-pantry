import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../storage/inventory_repo.dart';
import '../sync/sync_operation.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_ids.dart';
import '../utils/ingredient_normalizer.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

export 'storage_service_provider.dart' show inventorySeedProvider;

const inventoryItemsStorageKey = 'inventory_items';
const addHistoryStorageKey = 'add_history';
const inventoryFilterAll = '全部';
const inventoryFilterNotFresh = '不新鲜';
const _syncOperationIds = Uuid();

bool isNotFreshIngredient(Ingredient item) {
  return item.state == FreshnessState.expiringSoon ||
      item.state == FreshnessState.urgent ||
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
  late InventoryRepo _repo;

  @override
  List<Ingredient> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _save(List<Ingredient> items) async {
    _repo.saveItems(items);
  }

  Future<void> _enqueueSync({
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> patch,
    int? baseVersion,
  }) {
    final householdId = ref.read(selectedHouseholdIdProvider).trim();
    if (householdId.isEmpty || entityId.trim().isEmpty) {
      return Future.value();
    }

    final outbox = ref.read(syncOutboxRepoProvider);
    return outbox
        .enqueue(
          SyncOperation(
            id: _syncOperationIds.v4(),
            householdId: householdId,
            entityType: SyncEntityType.inventoryItem,
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

  Future<void> _enqueueSyncBatch(List<_PendingInventorySync> operations) async {
    for (final operation in operations) {
      await _enqueueSync(
        entityId: operation.entityId,
        operation: operation.operation,
        patch: operation.patch,
        baseVersion: operation.baseVersion,
      );
    }
  }

  Ingredient _withSyncId(Ingredient item) {
    final householdId = ref.read(selectedHouseholdIdProvider).trim();
    if (householdId.isEmpty || isUuid(item.id)) return item;
    return item.copyWith(id: newSyncEntityId());
  }

  Future<void> replaceFromRemote(List<Ingredient> items) async {
    final normalized = items
        .map(normalizeInventoryIngredient)
        .map(refreshIngredientFreshness)
        .toList(growable: false);
    state = normalized;
    await queuePersistence(() => _save(normalized));
  }

  Future<void> add(Ingredient item) async {
    final normalizedItem = normalizeIngredientCategory(_withSyncId(item));
    final stampedItem = normalizedItem.addedAt == null
        ? normalizedItem.copyWith(addedAt: DateTime.now())
        : normalizedItem;
    final itemToAdd = refreshIngredientFreshness(stampedItem);
    final prior = state;
    final updated = [...state, itemToAdd];
    state = updated;
    try {
      await queuePersistence(() async {
        await _save(updated);
        await ref.read(_addHistoryProvider.notifier).record(itemToAdd);
      }, rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSync(
      entityId: itemToAdd.id,
      operation: SyncOperationType.create,
      patch: itemToAdd.toJson(),
    );
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= state.length) return;
    final removed = state[index];
    final prior = state;
    final updated = [...state]..removeAt(index);
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    final deletedAt = DateTime.now().toUtc();
    await _enqueueSync(
      entityId: removed.id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: removed.remoteVersion,
    );
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    final normalizedItem = normalizeInventoryIngredient(_withSyncId(item));
    updated.insert(clampedIndex, normalizedItem);
    state = updated;
    await queuePersistence(() => _save(updated));
    await _enqueueSync(
      entityId: normalizedItem.id,
      operation: SyncOperationType.create,
      patch: normalizedItem.toJson(),
    );
  }

  Future<void> update(int index, Ingredient item) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    final original = state[index];
    final normalizedItem = normalizeIngredientCategory(item);
    final stampedItem = normalizedItem.addedAt == null
        ? normalizedItem.copyWith(addedAt: state[index].addedAt)
        : normalizedItem;
    final updatedItem = refreshIngredientFreshness(stampedItem);
    final prior = state;
    updated[index] = updatedItem;
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSync(
      entityId: updatedItem.id,
      operation: SyncOperationType.update,
      patch: updatedItem.toJson(),
      baseVersion: original.remoteVersion,
    );
  }

  /// Applies the selected Intake proposals and returns the set of proposal ids
  /// that were actually applied, so callers (e.g. the shopping list) only clean
  /// up the source rows whose intake really landed.
  Future<Set<String>> applyIntakeProposals(
    List<IntakeProposal> proposals,
  ) async {
    var current = [...state];
    final syncOperations = <_PendingInventorySync>[];
    final appliedIds = <String>{};
    for (final p in proposals) {
      if (!p.selected) continue;

      // Re-resolve the merge target against the LIVE inventory by the domain
      // identity rule — never a stale positional index captured at proposal
      // time (the list can reorder, shrink, or be restored from a persisted
      // draft across launches). A perishable / non-matching item falls back to
      // a new row, which can never corrupt an unrelated row.
      final mergeIndex = p.action == IntakeAction.mergeInto
          ? _findMergeTarget(current, p)
          : -1;

      if (mergeIndex < 0) {
        final item = _withSyncId(_ingredientFromProposal(p));
        current = [...current, item];
        syncOperations.add(
          _PendingInventorySync(
            entityId: item.id,
            operation: SyncOperationType.create,
            patch: item.toJson(),
          ),
        );
        appliedIds.add(p.id);
        continue;
      }

      final existing = current[mergeIndex];
      final summed = _sumQuantity(existing.quantity, p.quantity);
      final updatedItem = refreshIngredientFreshness(
        existing.copyWith(quantity: summed),
      );
      current = [...current]..[mergeIndex] = updatedItem;
      syncOperations.add(
        _PendingInventorySync(
          entityId: updatedItem.id,
          operation: SyncOperationType.intake,
          patch: updatedItem.toJson(),
          baseVersion: existing.remoteVersion,
        ),
      );
      appliedIds.add(p.id);
    }
    // Apply optimistically, then roll back if the local save fails so state and
    // disk never diverge and the Review can keep the draft for a retry.
    final prior = state;
    state = current;
    try {
      await queuePersistence(() => _save(current), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSyncBatch(syncOperations);
    return appliedIds;
  }

  /// Resolves the row a `mergeInto` proposal should merge into, by the domain
  /// merge rule (name+unit+storage) against the CURRENT inventory. Returns -1
  /// — meaning "create a new row instead" — when the item is Perishable (every
  /// intake is a new Batch), when no current row matches, or when the matching
  /// row's quantity is non-numeric (merging would silently discard its stock).
  int _findMergeTarget(List<Ingredient> current, IntakeProposal p) {
    if (_isPerishableProposal(p)) return -1;
    final name = p.name.trim().toLowerCase();
    final unit = p.unit.trim();
    if (name.isEmpty || unit.isEmpty) return -1;
    for (var i = 0; i < current.length; i++) {
      final row = current[i];
      if (row.name.trim().toLowerCase() != name) continue;
      if (row.unit.trim() != unit) continue;
      if (row.storage != p.storage) continue;
      if (double.tryParse(row.quantity.trim()) == null) return -1;
      return i;
    }
    return -1;
  }

  bool _isPerishableProposal(IntakeProposal p) {
    return FoodCategories.isPerishable(p.category) ||
        FoodKnowledge.isPerishableName(p.name);
  }

  Future<void> applyDeductionProposals(
    List<DeductionProposal> proposals,
  ) async {
    var current = [...state];

    // Resolve every selected deduction to a LIVE row index by stable identity,
    // and aggregate per row so two proposals that resolve to the same row net
    // into one deduction (and one sync op) instead of double-deducting /
    // double-deleting against a stale snapshot.
    final deductByIndex = <int, double>{};
    for (final p in proposals) {
      if (!p.selected) continue;
      if (p.action == DeductionAction.skip) continue;
      final chosen = _chosenCandidate(p);
      if (chosen == null) continue;
      final amount = double.tryParse(p.deductAmount.trim());
      if (amount == null || amount <= 0) continue; // never silently deduct 0
      final index = _resolveDeductionRow(current, chosen);
      if (index < 0) continue; // row gone / ambiguous -> skip the wrong-row risk
      deductByIndex.update(index, (v) => v + amount, ifAbsent: () => amount);
    }

    final removalIndices = <int>{};
    final syncOperations = <_PendingInventorySync>[];
    deductByIndex.forEach((index, totalDeduct) {
      final existing = current[index];
      final existingQty = double.tryParse(existing.quantity.trim());
      // Non-numeric stock (e.g. "适量", "半盒") must not be coerced to 0 and
      // deleted — leave the row untouched rather than wiping real inventory.
      if (existingQty == null) return;
      final remaining = existingQty - totalDeduct;
      if (remaining <= 0) {
        removalIndices.add(index);
        final deletedAt = DateTime.now().toUtc();
        syncOperations.add(
          _PendingInventorySync(
            entityId: existing.id,
            operation: SyncOperationType.delete,
            patch: {'deletedAt': deletedAt.toIso8601String()},
            baseVersion: existing.remoteVersion,
          ),
        );
      } else {
        final updatedItem = refreshIngredientFreshness(
          existing.copyWith(quantity: _formatQuantity(remaining)),
        );
        current[index] = updatedItem;
        syncOperations.add(
          _PendingInventorySync(
            entityId: updatedItem.id,
            operation: SyncOperationType.deduction,
            patch: updatedItem.toJson(),
            baseVersion: existing.remoteVersion,
          ),
        );
      }
    });

    if (removalIndices.isNotEmpty) {
      final sortedDesc = removalIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final idx in sortedDesc) {
        current.removeAt(idx);
      }
    }
    final prior = state;
    state = List<Ingredient>.from(current);
    try {
      await queuePersistence(() => _save(state), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await _enqueueSyncBatch(syncOperations);
  }

  DeductionCandidate? _chosenCandidate(DeductionProposal p) {
    for (final candidate in p.candidates) {
      if (candidate.inventoryRowIndex == p.chosenIndex) return candidate;
    }
    return null;
  }

  /// Resolves the live inventory index for a chosen deduction candidate by
  /// stable identity, defending against list reordering between proposal
  /// creation and apply. Prefers the row id (household-synced rows); for
  /// local-only rows whose id is empty, falls back to the recorded positional
  /// index guarded by the captured row name, so a deduction never lands on an
  /// unrelated row. Returns -1 when the target can no longer be identified.
  int _resolveDeductionRow(List<Ingredient> current, DeductionCandidate chosen) {
    final id = chosen.inventoryRowId.trim();
    if (id.isNotEmpty) {
      final matches = <int>[];
      for (var i = 0; i < current.length; i++) {
        if (current[i].id == id) matches.add(i);
      }
      if (matches.length == 1) return matches.first;
      // 0 or ambiguous by id -> fall through to the name-guarded index path.
    }
    final index = chosen.inventoryRowIndex;
    if (index < 0 || index >= current.length) return -1;
    final expectedName = chosen.inventoryRowName.trim().toLowerCase();
    if (expectedName.isEmpty) return index; // no captured identity -> trust index
    if (current[index].name.trim().toLowerCase() == expectedName) return index;
    // Index drifted; recover only if exactly one row still carries the name.
    final byName = <int>[];
    for (var j = 0; j < current.length; j++) {
      if (current[j].name.trim().toLowerCase() == expectedName) byName.add(j);
    }
    return byName.length == 1 ? byName.first : -1;
  }

  String _formatQuantity(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  Ingredient _ingredientFromProposal(IntakeProposal p) {
    final shelf = p.shelfLifeDays;
    final addedAt = DateTime.now();
    final expiryDate = shelf == null
        ? null
        : addedAt.add(Duration(days: shelf));
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
    await queuePersistence(() => _save(updated));
    await _enqueueSync(
      entityId: mergedTarget.id,
      operation: SyncOperationType.update,
      patch: mergedTarget.toJson(),
      baseVersion: target.remoteVersion,
    );
    final deletedAt = DateTime.now().toUtc();
    await _enqueueSync(
      entityId: source.id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: source.remoteVersion,
    );
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

class _PendingInventorySync {
  const _PendingInventorySync({
    required this.entityId,
    required this.operation,
    required this.patch,
    this.baseVersion,
  });

  final String entityId;
  final SyncOperationType operation;
  final Map<String, dynamic> patch;
  final int? baseVersion;
}

class _AddHistoryNotifier extends Notifier<List<FrequentItem>> {
  late InventoryRepo _repo;

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
      final rememberedCategory = category is String
          ? category
          : defaults?.category;

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
  const maxCapacity = {
    IconType.fridge: 20,
    IconType.freezer: 20,
    IconType.pantry: 50,
  };
  const names = {
    IconType.fridge: '冰箱',
    IconType.freezer: '冷冻室',
    IconType.pantry: '食品柜',
  };
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
  final presentNames = inventory
      .map((i) => i.name.trim().toLowerCase())
      .toSet();

  final filtered = all
      .where((f) => f.count >= 3)
      .where((f) => !presentNames.contains(f.name.trim().toLowerCase()))
      .toList();
  filtered.sort((a, b) => b.count.compareTo(a.count));
  return filtered;
});
