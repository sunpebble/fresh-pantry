import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/search_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container({List<Ingredient>? inventory}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...testStorageOverrides(database: db, inventory: inventory ?? const []),
    ],
  );
}

Ingredient _ing(String name, {String? category}) => Ingredient(
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
  category: category ?? '测试',
  storage: IconType.fridge,
);

void main() {
  group('filteredInventoryProvider', () {
    test('returns all items when keyword is empty', () async {
      final c = await _container(inventory: [_ing('苹果'), _ing('牛奶')]);
      addTearDown(c.dispose);

      expect(c.read(filteredInventoryProvider).map((i) => i.name), ['苹果', '牛奶']);
    });

    test('filters by name (case-insensitive for ASCII)', () async {
      final c = await _container(
        inventory: [_ing('apple'), _ing('orange'), _ing('苹果')],
      );
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = 'APPLE';
      expect(c.read(filteredInventoryProvider).map((i) => i.name), ['apple']);
    });

    test('matches category as well as name', () async {
      final c = await _container(
        inventory: [_ing('鸡蛋', category: '乳品蛋类'), _ing('番茄', category: '果蔬')],
      );
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = '乳';
      expect(c.read(filteredInventoryProvider).map((i) => i.name), ['鸡蛋']);
    });

    test('returns empty list when no items match', () async {
      final c = await _container(inventory: [_ing('苹果'), _ing('牛奶')]);
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = 'XYZ不存在';
      expect(c.read(filteredInventoryProvider), isEmpty);
    });

    test('returns all items when keyword is only whitespace', () async {
      final c = await _container(inventory: [_ing('苹果'), _ing('牛奶')]);
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = '   ';
      expect(c.read(filteredInventoryProvider).length, 2);
    });
  });

  group('SearchHistoryNotifier', () {
    ProviderContainer makeContainer() => ProviderContainer();

    test('starts empty', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(searchHistoryProvider), isEmpty);
    });

    test('add inserts term at front', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      n.add('苹果');
      n.add('牛奶');
      expect(c.read(searchHistoryProvider).first, '牛奶');
    });

    test('add deduplicates: existing term moves to front', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      n.add('苹果');
      n.add('牛奶');
      n.add('苹果');
      expect(c.read(searchHistoryProvider), ['苹果', '牛奶']);
    });

    test('add caps at 10 items', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      for (var i = 0; i < 12; i++) {
        n.add('item$i');
      }
      expect(c.read(searchHistoryProvider).length, 10);
    });

    test('add ignores blank/whitespace-only terms', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      n.add('');
      n.add('   ');
      expect(c.read(searchHistoryProvider), isEmpty);
    });

    test('remove deletes a term', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      n.add('苹果');
      n.add('牛奶');
      n.remove('苹果');
      expect(c.read(searchHistoryProvider), ['牛奶']);
    });

    test('clear empties history', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      final n = c.read(searchHistoryProvider.notifier);
      n.add('苹果');
      n.add('牛奶');
      n.clear();
      expect(c.read(searchHistoryProvider), isEmpty);
    });
  });

  group('searchFoodDetailsProvider', () {
    test('returns null immediately for keyword shorter than 2 chars', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = 'a';
      final result = await c.read(searchFoodDetailsProvider.future);
      expect(result, isNull);
    });

    test('returns null for empty keyword', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      c.read(searchProvider.notifier).state = '';
      final result = await c.read(searchFoodDetailsProvider.future);
      expect(result, isNull);
    });
  });
}
