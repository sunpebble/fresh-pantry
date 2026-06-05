import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/ingredient_identity.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../storage/inventory_repo.dart';
import '../sync/sync_enqueue.dart';
import '../sync/sync_ids.dart';
import '../sync/sync_operation.dart';
import '../utils/ingredient_normalizer.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

export 'storage_service_provider.dart' show inventorySeedProvider;

const inventoryFilterAll = '全部';
const inventoryFilterNotFresh = '不新鲜';

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
    with PersistenceQueue, SyncEnqueue<List<Ingredient>> {
  late InventoryRepo _repo;

  @override
  SyncEntityType get syncEntityType => SyncEntityType.inventoryItem;

  @override
  List<Ingredient> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _repo.loadAll();
  }

  /// 下拉刷新：从本地 DB(按当前 household 作用域)重读。
  ///
  /// 不能用 `ref.invalidate(inventoryProvider)`——`build()` 返回的是
  /// main.dart 启动时注入的一次性种子(`loadAll()` 读完即清空),重建时种子
  /// 已被消费,只会落回空列表(下拉刷新瞬间清空的根因)。本地 DB 才是持续的
  /// 真相源(每次增删改与 sync 都同步写盘),所以直接重读即可,且 `loadAllFor`
  /// 内部已按 `now` 重算新鲜度。
  Future<void> reload() async {
    state = await _repo.loadAllFor(activeHouseholdId);
  }

  Future<void> _save(List<Ingredient> items) async {
    await _repo.saveItems(activeHouseholdId, items);
  }

  /// Every inventory item is born with a stable sync UUID — local-only or not.
  /// Blank/non-UUID ids were the root of duplicate rows: each household
  /// transition minted a *fresh* id for the same logical item, so cloning it.
  Ingredient _withSyncId(Ingredient item) {
    if (isUuid(item.id)) return item;
    return item.copyWith(id: newSyncEntityId());
  }

  /// Replaces the whole list and persists it. The sync inflow leaves
  /// [rethrowOnError] false (a failed local write is swallowed; sync retries).
  /// Backup restore passes true so a failed write rolls back and propagates —
  /// a destructive "restore complete" message must never lie about data that
  /// never reached disk.
  Future<void> replaceFromRemote(
    List<Ingredient> items, {
    bool rethrowOnError = false,
  }) async {
    final normalized = items
        .map(normalizeInventoryIngredient)
        .map(refreshIngredientFreshness)
        .toList(growable: false);
    final prior = state;
    state = normalized;
    try {
      await queuePersistence(
        () => _save(normalized),
        rethrowError: rethrowOnError,
      );
    } catch (_) {
      state = prior;
      rethrow;
    }
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
        await ref.read(addHistoryProvider.notifier).record(itemToAdd);
      }, rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await enqueueSync(
      entityId: itemToAdd.id,
      operation: SyncOperationType.create,
      patch: itemToAdd.toJson(),
    );
  }

  /// 手动删除食材后,把补货频次记忆里对应的名称抹掉——删除即"不要了",
  /// 不该再在「库存不足」里提醒补货。仅对删除后库存里已无同名残留的名称生效
  /// (大小写/空格不敏感,与 [lowStockItemsProvider] 的判定一致),所以删掉一盒
  /// 牛奶时另一盒还在就不会误清。消费扣减/合并不走这里:吃完才是该补货的时刻。
  Future<void> _forgetRemovedNames(Iterable<String> names) async {
    final present = state.map((i) => i.name.trim().toLowerCase()).toSet();
    final vanished = <String>{
      for (final name in names)
        if (!present.contains(name.trim().toLowerCase())) name,
    };
    if (vanished.isEmpty) return;
    final history = ref.read(addHistoryProvider.notifier);
    for (final name in vanished) {
      await history.forget(name);
    }
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
    await enqueueSync(
      entityId: removed.id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: removed.remoteVersion,
    );
    await _forgetRemovedNames([removed.name]);
  }

  /// Removes every inventory row at once (the "clear all" action). Optimistic
  /// with rollback so disk never diverges from state, then enqueues a delete per
  /// removed row so other household members see the clear too.
  Future<void> clearAll() async {
    if (state.isEmpty) return;
    final removed = state;
    final deletedAt = DateTime.now().toUtc();
    final syncOperations = removed
        .map(
          (item) => SyncEnqueueOp(
            entityId: item.id,
            operation: SyncOperationType.delete,
            patch: {'deletedAt': deletedAt.toIso8601String()},
            baseVersion: item.remoteVersion,
          ),
        )
        .toList(growable: false);
    state = const <Ingredient>[];
    try {
      await queuePersistence(
        () => _save(const <Ingredient>[]),
        rethrowError: true,
      );
    } catch (_) {
      state = removed;
      rethrow;
    }
    await enqueueSyncBatch(syncOperations);
    await _forgetRemovedNames(removed.map((item) => item.name));
  }

  /// Removes every [targets] row at once (the multi-select "batch delete").
  ///
  /// Each target is resolved to its live index by stable identity (so a
  /// reordered display list never deletes the wrong row), removed optimistically
  /// with rollback, then a delete is enqueued per row so other household members
  /// see it too. Returns the removed items paired with their original indices,
  /// ascending, so the caller can undo by re-inserting each at its position.
  Future<List<({int index, Ingredient item})>> removeMany(
    Iterable<Ingredient> targets,
  ) async {
    final indices = <int>{};
    for (final target in targets) {
      final index = inventoryIndexOf(state, target);
      if (index != -1) indices.add(index);
    }
    if (indices.isEmpty) return const [];

    final ascending = indices.toList()..sort();
    final removed = [for (final i in ascending) (index: i, item: state[i])];

    final prior = state;
    final updated = [...state];
    for (final i in ascending.reversed) {
      updated.removeAt(i);
    }
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    final deletedAt = DateTime.now().toUtc();
    await enqueueSyncBatch([
      for (final r in removed)
        SyncEnqueueOp(
          entityId: r.item.id,
          operation: SyncOperationType.delete,
          patch: {'deletedAt': deletedAt.toIso8601String()},
          baseVersion: r.item.remoteVersion,
        ),
    ]);
    await _forgetRemovedNames(removed.map((r) => r.item.name));
    return removed;
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    final normalizedItem = normalizeInventoryIngredient(_withSyncId(item));
    updated.insert(clampedIndex, normalizedItem);
    state = updated;
    await queuePersistence(() => _save(updated));
    await enqueueSync(
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
    await enqueueSync(
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
    final syncOperations = <SyncEnqueueOp>[];
    final appliedIds = <String>{};
    for (final p in proposals) {
      if (!p.selected) continue;

      // Re-resolve the merge target against the LIVE inventory by the domain
      // identity rule — never a stale positional index captured at proposal
      // time (the list can reorder, shrink, or be restored from a persisted
      // draft across launches). A perishable / non-matching item falls back to
      // a new row, which can never corrupt an unrelated row.
      final mergeIndex = p.action == IntakeAction.mergeInto
          ? IngredientIdentity.resolveMergeTarget(
              name: p.name,
              unit: p.unit,
              storage: p.storage,
              category: p.category,
              inventory: current,
            )
          : -1;

      if (mergeIndex < 0) {
        final item = _withSyncId(_ingredientFromProposal(p));
        current = [...current, item];
        syncOperations.add(
          SyncEnqueueOp(
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
        SyncEnqueueOp(
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
    await enqueueSyncBatch(syncOperations);
    return appliedIds;
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
      if (index < 0) {
        continue; // row gone / ambiguous -> skip the wrong-row risk
      }
      deductByIndex.update(index, (v) => v + amount, ifAbsent: () => amount);
    }

    final removalIndices = <int>{};
    final syncOperations = <SyncEnqueueOp>[];
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
          SyncEnqueueOp(
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
          SyncEnqueueOp(
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
    await enqueueSyncBatch(syncOperations);
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
  int _resolveDeductionRow(
    List<Ingredient> current,
    DeductionCandidate chosen,
  ) {
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
    if (expectedName.isEmpty) {
      return index; // no captured identity -> trust index
    }
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
    await enqueueSync(
      entityId: mergedTarget.id,
      operation: SyncOperationType.update,
      patch: mergedTarget.toJson(),
      baseVersion: target.remoteVersion,
    );
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
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

/// UI-state ViewModel over the add-history frequency memory. Holds only the
/// derived [FrequentItem] list; all raw-map decoding and the record/forget
/// merge logic live in [InventoryRepo] (the repo owns raw->domain).
class _AddHistoryNotifier extends Notifier<List<FrequentItem>> {
  late InventoryRepo _repo;

  @override
  List<FrequentItem> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _repo.loadFrequentItems();
  }

  Future<void> record(Ingredient item) async {
    await _repo.recordAddition(item);
    state = _repo.loadFrequentItems();
  }

  /// 把某个名称从补货频次记忆中抹掉(手动删除食材时调用)。不存在则 no-op。
  Future<void> forget(String name) async {
    await _repo.forgetAddition(name);
    state = _repo.loadFrequentItems();
  }
}

final addHistoryProvider =
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
  final all = [...ref.watch(addHistoryProvider)];
  all.sort((a, b) => b.count.compareTo(a.count));
  return all.where((i) => i.count >= 2).take(6).toList();
});

final lowStockItemsProvider = Provider.autoDispose<List<FrequentItem>>((ref) {
  final all = ref.watch(addHistoryProvider);
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
