import 'package:drift/drift.dart';

import '../models/shopping_item.dart';
// The drift-generated shopping row data class is also named `ShoppingItem`,
// which collides with the model imported above. Hide it; the repo only needs
// the database + table accessors, never the generated row type directly.
import 'drift/app_database.dart' hide ShoppingItem;
import 'drift/entity_row_codec.dart';
import 'shopping_item_normalizer.dart';

class ShoppingRepo {
  ShoppingRepo(this._db);

  final AppDatabase _db;
  List<ShoppingItem>? _hydratedSeed;

  void hydrate(List<ShoppingItem> seed) => _hydratedSeed = seed;

  List<ShoppingItem> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  Future<List<ShoppingItem>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.shoppingItems)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final items = <ShoppingItem>[];
    for (final row in rows) {
      try {
        items.add(normalizeShoppingItemCategory(shoppingFromRow(row)));
      } catch (_) {
        // skip malformed
      }
    }
    return deduplicateShoppingItems(items);
  }

  Future<void> saveItems(String householdId, List<ShoppingItem> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.shoppingItems)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.shoppingItems,
          items.map((s) => shoppingCompanionFor(householdId, s)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
