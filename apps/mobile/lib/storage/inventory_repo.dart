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
