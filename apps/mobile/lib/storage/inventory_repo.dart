import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/ingredient.dart';
import '../utils/ingredient_normalizer.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

class InventoryRepo {
  InventoryRepo(this._db);

  final AppDatabase _db;
  List<Ingredient>? _hydratedSeed;
  Map<String, dynamic> _history = const {};

  /// 预读种子(main.dart 预读注入)，保持 Notifier.build() 同步契约。
  void hydrate(List<Ingredient> seed) => _hydratedSeed = seed;

  /// 同步取一次种子；无种子时返回空(切换 household 走异步 loadAllFor)。
  List<Ingredient> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  /// 按 household 作用域异步读取(并按现有规则归一化)。
  Future<List<Ingredient>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final items = <Ingredient>[];
    for (final row in rows) {
      try {
        items.add(normalizeInventoryIngredient(ingredientFromRow(row)));
      } catch (_) {
        // 跳过单条坏数据，保留其余。
      }
    }
    return items;
  }

  /// 事务内替换该 household 的全部行(删除 + 批量 upsert)。
  Future<void> saveItems(String householdId, List<Ingredient> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.inventoryItems)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.inventoryItems,
          items.map((i) => inventoryCompanionFor(householdId, i)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  /// 按 id 增量 upsert 一行(热路径，避免全量 delete-all + insert-all)。
  ///
  /// InventoryItems 主键是 surrogate `rowPk`，不是 `id`，所以
  /// `insertOnConflictUpdate` 无法按 id 去重——必须事务内先删该 household 作用域
  /// 内同 id 的行，再插入，保证同一 id 重复 upsert 不留多行。
  Future<void> upsert(String householdId, Ingredient item) {
    return _db.transaction(() async {
      await (_db.delete(_db.inventoryItems)
            ..where(
              (t) => t.householdId.equals(householdId) & t.id.equals(item.id),
            ))
          .go();
      await _db
          .into(_db.inventoryItems)
          .insert(inventoryCompanionFor(householdId, item));
    });
  }

  /// 本地物理删除该 household 作用域内的一行(同步层另发软删除 op 给远端)。
  Future<void> softDelete(String householdId, String id) {
    return (_db.delete(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId) & t.id.equals(id)))
        .go();
  }

  /// 响应式读取该 household 作用域的全部行(本 Task 仅提供 + 单测覆盖，未接 UI)。
  Stream<List<Ingredient>> watchAllFor(String householdId) {
    return (_db.select(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .watch()
        .map((rows) => rows.map(ingredientFromRow).toList());
  }

  // --- add_history (本地频次记忆，非同步) ---
  Map<String, dynamic> loadHistory() => _history;

  /// 预读 history 到内存(main.dart 调用)。
  Future<void> hydrateHistory() async {
    final rows = await _db.select(_db.addHistoryEntries).get();
    _history = {
      for (final r in rows) r.name: jsonDecode(r.payloadJson),
    };
  }

  Future<void> saveHistory(Map<String, dynamic> history) async {
    _history = Map<String, dynamic>.from(history);
    await _db.transaction(() async {
      await _db.delete(_db.addHistoryEntries).go();
      await _db.batch((b) {
        b.insertAll(
          _db.addHistoryEntries,
          history.entries.map(
            (e) => AddHistoryEntriesCompanion.insert(
              name: e.key,
              payloadJson: jsonEncode(e.value),
            ),
          ),
        );
      });
    });
  }

  Future<void> clearHistory() => saveHistory(const {});
}
