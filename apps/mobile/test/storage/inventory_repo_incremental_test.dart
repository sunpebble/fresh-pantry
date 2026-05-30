import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

import '../support/test_database.dart';

Ingredient _ing(String id, String name) => Ingredient(
  id: id,
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
);

void main() {
  late AppDatabase db;
  late InventoryRepo repo;

  setUp(() {
    db = newTestDatabase();
    repo = InventoryRepo(db);
    addTearDown(db.close);
  });

  test('upsert affects only the target row', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶'), _ing('b', '蛋')]);

    await repo.upsert('h1', _ing('a', '低脂牛奶'));

    final names = (await repo.loadAllFor('h1')).map((e) => e.name).toSet();
    expect(names, {'低脂牛奶', '蛋'});
  });

  test('upserting the same id twice leaves a single row', () async {
    // The InventoryItems primary key is a surrogate `rowPk`, so a naive
    // insertOnConflictUpdate would NOT dedupe by `id` and would leave two rows.
    // upsert must delete the same-id row in scope before inserting.
    await repo.upsert('h1', _ing('a', '牛奶'));
    await repo.upsert('h1', _ing('a', '低脂牛奶'));

    final items = await repo.loadAllFor('h1');
    expect(items, hasLength(1));
    expect(items.single.name, '低脂牛奶');
  });

  test('softDelete removes only the target row from the scope', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶'), _ing('b', '蛋')]);

    await repo.softDelete('h1', 'a');

    final names = (await repo.loadAllFor('h1')).map((e) => e.name).toSet();
    expect(names, {'蛋'});
  });

  test('upsert and softDelete are scoped to the household', () async {
    await repo.saveItems('h1', [_ing('a', '牛奶')]);
    await repo.saveItems('h2', [_ing('a', '酸奶')]);

    // Same id, different household: must not touch the other scope's row.
    await repo.upsert('h1', _ing('a', '低脂牛奶'));
    expect((await repo.loadAllFor('h2')).single.name, '酸奶');

    await repo.softDelete('h1', 'a');
    expect(await repo.loadAllFor('h1'), isEmpty);
    expect((await repo.loadAllFor('h2')).single.name, '酸奶');
  });

  test('watchAllFor pushes the latest scope contents on change', () async {
    final emissions = <List<String>>[];
    final sub = repo
        .watchAllFor('h1')
        .listen((items) => emissions.add(items.map((e) => e.name).toList()));

    await repo.upsert('h1', _ing('a', '牛奶'));
    await repo.upsert('h1', _ing('b', '蛋'));
    await repo.softDelete('h1', 'a');

    // Let the stream settle on the final state.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(emissions.last, ['蛋']);
  });
}
