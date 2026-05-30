import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

Ingredient _ing(String id, String name, {int v = 0}) => Ingredient(
      id: id, name: name, quantity: '1', unit: '个', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh, remoteVersion: v,
    );

void main() {
  late AppDatabase db;
  late InventoryRepo repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryRepo(db);
  });
  tearDown(() => db.close());

  test('saveItems then loadAllFor is scoped by household', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶')]);
    await repo.saveItems('h2', [_ing('b', '鸡蛋')]);
    expect((await repo.loadAllFor('h1')).map((e) => e.name), ['牛奶']);
    expect((await repo.loadAllFor('h2')).map((e) => e.name), ['鸡蛋']);
  });

  test('saveItems replaces the scope, not other households', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶'), _ing('c', '面包')]);
    await repo.saveItems('h2', [_ing('b', '鸡蛋')]);
    await repo.saveItems('h1', [_ing('a', '牛奶')]); // 删除 c
    expect((await repo.loadAllFor('h1')).map((e) => e.id), ['a']);
    expect((await repo.loadAllFor('h2')).map((e) => e.id), ['b']);
  });

  test('add history persists and round-trips', () async {
    await repo.saveHistory({'牛奶': {'count': 3, 'unit': '盒'}});
    expect(repo.loadHistory()['牛奶'], {'count': 3, 'unit': '盒'});
    await repo.clearHistory();
    expect(repo.loadHistory(), isEmpty);
  });
}
