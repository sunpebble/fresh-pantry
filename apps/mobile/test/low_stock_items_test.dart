import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container({
  required Map<String, dynamic> history,
  required List<Ingredient> inventory,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  // add_history is local frequency memory backed by Drift now (not the prefs
  // blob), so seed it through a preloaded InventoryRepo: hydrate() feeds the
  // synchronous build() snapshot and saveHistory() populates loadHistory().
  final repo = InventoryRepo(db);
  repo.hydrate(inventory);
  await repo.saveHistory(history);
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appDatabaseProvider.overrideWithValue(db),
    inventoryRepoProvider.overrideWithValue(repo),
  ]);
}

Ingredient _ing(String name) => Ingredient(
      name: name,
      quantity: '1',
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.fridge,
    );

Map<String, dynamic> _entry(int count, {String unit = '个'}) => {
      'count': count,
      'category': FoodCategories.other,
      'storage': 'fridge',
      'unit': unit,
    };

void main() {
  test('returns frequent items not currently in inventory, count>=3', () async {
    final c = await _container(
      history: {
        '米': _entry(5),
        '鸡蛋': _entry(3),
        '葱': _entry(2), // count < 3 → excluded
      },
      inventory: [_ing('米')], // 米 present → excluded
    );
    final result = c.read(lowStockItemsProvider);
    expect(result.map((f) => f.name), ['鸡蛋']);
  });

  test('empty history returns empty', () async {
    final c = await _container(history: {}, inventory: []);
    expect(c.read(lowStockItemsProvider), isEmpty);
  });

  test('name matching case+whitespace-insensitive', () async {
    final c = await _container(
      history: {'鸡蛋': _entry(5)},
      inventory: [_ing(' 鸡蛋 ')], // whitespace differs
    );
    expect(c.read(lowStockItemsProvider), isEmpty,
        reason: 'whitespace-differing name still counts as present');
  });

  test('sorted by count descending', () async {
    final c = await _container(
      history: {'A': _entry(5), 'B': _entry(3), 'C': _entry(4)},
      inventory: [],
    );
    final names = c.read(lowStockItemsProvider).map((f) => f.name).toList();
    expect(names, ['A', 'C', 'B']);
  });
}
