import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
// Hide the drift-generated row class `ShoppingItem`, which collides with the
// model `ShoppingItem`; the test only needs `AppDatabase` from this import.
import 'package:fresh_pantry/storage/drift/app_database.dart' hide ShoppingItem;
import 'package:fresh_pantry/storage/shopping_repo.dart';

ShoppingItem _s(String id, String name) =>
    ShoppingItem(id: id, name: name, detail: '', category: '其他');

void main() {
  late AppDatabase db;
  late ShoppingRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ShoppingRepo(db);
  });
  tearDown(() => db.close());

  test('saveItems scoped + dedup on load', () async {
    await repo.saveItems('h1', [_s('a', '牛奶'), _s('b', '牛奶')]);
    final loaded = await repo.loadAllFor('h1');
    expect(loaded.length, 1); // deduplicateShoppingItems 生效
  });
}
