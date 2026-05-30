import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing({
  required String qty,
  DateTime? expiry,
}) =>
    Ingredient(
      name: '牛奶',
      quantity: qty,
      unit: '盒',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      expiryDate: expiry,
    );

void main() {
  test('mergeBatch sums qty and keeps earlier expiry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([
        _ing(qty: '1', expiry: DateTime(2026, 5, 30)), // 0: later expiry
        _ing(qty: '1', expiry: DateTime(2026, 5, 20)), // 1: earlier expiry
      ]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 1);
    final s = c.read(inventoryProvider);
    expect(s.length, 1);
    expect(s.first.quantity, '2');
    expect(s.first.expiryDate, DateTime(2026, 5, 20),
        reason: 'must take earlier of the two expiries');
  });

  test('mergeBatch sourceIndex > targetIndex: sums qty and keeps earlier expiry', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([
        _ing(qty: '3', expiry: DateTime(2026, 6, 1)), // 0: target
        _ing(qty: '2', expiry: DateTime(2026, 5, 15)), // 1: source
      ]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(1, 0);
    final s = c.read(inventoryProvider);
    expect(s.length, 1);
    expect(s.first.quantity, '5');
    expect(s.first.expiryDate, DateTime(2026, 5, 15),
        reason: 'must take earlier of the two expiries');
  });

  test('mergeBatch no-op when same index', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([
        _ing(qty: '2', expiry: DateTime(2026, 5, 20)),
      ]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 0);
    expect(c.read(inventoryProvider).length, 1);
  });

  test('mergeBatch no-op when out of range', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([
        _ing(qty: '1'),
      ]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 5);
    expect(c.read(inventoryProvider).length, 1);
  });

  test('mergeBatch no-op when units differ', () async {
    SharedPreferences.setMockInitialValues({});
    final a = Ingredient(
      name: '牛奶',
      quantity: '1',
      unit: '盒',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
    );
    final b = a.copyWith(unit: '瓶');
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance()),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([a, b]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 1);
    expect(c.read(inventoryProvider).length, 2);
  });

  test('mergeBatch no-op when storage differs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = Ingredient(
      name: '牛奶',
      quantity: '1',
      unit: '盒',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
    );
    final b = a.copyWith(storage: IconType.pantry);
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([a, b]),
    ]);
    final n = c.read(inventoryProvider.notifier);
    await n.mergeBatch(0, 1);
    expect(c.read(inventoryProvider).length, 2);
  });

  test('_earlierExpiry: null a returns b', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Test via mergeBatch: source has null expiry, target has a date
    final source = Ingredient(
      name: '牛奶',
      quantity: '1',
      unit: '盒',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      expiryDate: null,
    );
    final target = source.copyWith(
        quantity: '2', expiryDate: DateTime(2026, 5, 20));
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue([source, target]),
    ]);
    await c.read(inventoryProvider.notifier).mergeBatch(0, 1);
    final s = c.read(inventoryProvider);
    expect(s.length, 1);
    expect(s.first.quantity, '3');
    expect(s.first.expiryDate, DateTime(2026, 5, 20));
  });
}
