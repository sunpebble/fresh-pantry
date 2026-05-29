import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';

import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/themealdb_service.dart';
import 'package:fresh_pantry/utils/expiry_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('provider rebuilds', () {
    test(
      'InventoryNotifier can rebuild without reinitialization errors',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(inventoryProvider), isEmpty);

        container.invalidate(inventoryProvider);

        expect(container.read(inventoryProvider), isEmpty);
      },
    );

    test(
      'ShoppingNotifier can rebuild without reinitialization errors',
      () async {
        SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(shoppingProvider), isEmpty);

        container.invalidate(shoppingProvider);

        expect(container.read(shoppingProvider), isEmpty);
      },
    );
  });

  group('InventoryNotifier.add', () {
    test(
      'saves inventory when add history contains old numeric counts',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({'牛奶': 1}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(inventoryProvider.notifier).add(_ingredient('牛奶')),
          completes,
        );

        final savedInventory = json.decode(prefs.getString('inventory_items')!);
        expect(savedInventory, isA<List<dynamic>>());
        expect(savedInventory, hasLength(1));
        expect(savedInventory.single['name'], '牛奶');

        final history = json.decode(prefs.getString('add_history')!);
        expect(history['牛奶']['count'], 2);
      },
    );

    test(
      'updates watched frequent items immediately after add completes',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({
            '鸡蛋': {
              'count': 1,
              'category': '蛋类',
              'storage': 'fridge',
              'unit': '个',
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        container.listen(
          frequentItemsProvider,
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(inventoryProvider.notifier).add(_ingredient('鸡蛋'));

        final frequentItems = container.read(frequentItemsProvider);
        expect(frequentItems.map((item) => item.name), contains('鸡蛋'));
        expect(frequentItems.singleWhere((item) => item.name == '鸡蛋').count, 2);
      },
    );

    test(
      'updates inventory state before the returned future completes',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final add = container
            .read(inventoryProvider.notifier)
            .add(_ingredient('番茄'));

        expect(container.read(inventoryProvider).map((item) => item.name), [
          '番茄',
        ]);
        await add;
      },
    );

    test('exposes only the fixed inventory filter categories', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([
          _ingredient('番茄').copyWith(category: '蔬菜').toJson(),
          _ingredient('自定义食材').copyWith(category: '自定义分类').toJson(),
        ]),
        'add_history': json.encode({}),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(categoriesProvider), [
        inventoryFilterAll,
        ...FoodCategories.values,
      ]);
    });

    test(
      'loads valid inventory rows when persisted list has bad rows',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': json.encode([
            _ingredient('番茄').toJson(),
            'bad row',
            {'name': '牛奶', 'quantity': '1'},
          ]),
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(inventoryProvider).map((item) => item.name), [
          '番茄',
          '牛奶',
        ]);
      },
    );

    test('shows newly added items first in recent additions', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'add_history': json.encode({}),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).add(_ingredient('黄瓜'));

      final recentItems = container.read(recentAdditionsProvider);
      expect(recentItems.map((item) => item.name), ['黄瓜']);
    });

    test('stamps newly added items with an added time', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'add_history': json.encode({}),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).add(_ingredient('黄瓜'));

      final item = container.read(inventoryProvider).single;
      expect(item.addedAt, isNotNull);

      final savedInventory = json.decode(prefs.getString('inventory_items')!);
      expect(savedInventory.single['addedAt'], isA<String>());
    });

    test('recalculates freshness from saved expiry dates on load', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final savedItem = Ingredient(
        name: '测试叶菜',
        quantity: '1',
        unit: '份',
        imageUrl: '',
        freshnessPercent: 1,
        state: FreshnessState.fresh,
        category: '测试',
        storage: IconType.fridge,
        expiryDate: today.add(const Duration(days: 1)),
        addedAt: today.subtract(const Duration(days: 2)),
      );
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([savedItem.toJson()]),
        'add_history': json.encode({}),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final item = container.read(inventoryProvider).single;

      expect(item.freshnessPercent, closeTo(1 / 3, 0.001));
      // Expiring tomorrow is within the urgent window.
      expect(item.state, FreshnessState.urgent);
      expect(item.expiryLabel, '明天过期');
    });

    test(
      'uses saved shelf life instead of remaining days for freshness',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final savedItem = Ingredient(
          name: '测试叶菜',
          quantity: '1',
          unit: '瓶',
          imageUrl: '',
          freshnessPercent: 1,
          state: FreshnessState.fresh,
          category: '测试',
          storage: IconType.fridge,
          expiryDate: today.add(const Duration(days: 1)),
          addedAt: today,
          shelfLifeDays: 7,
        );
        SharedPreferences.setMockInitialValues({
          'inventory_items': json.encode([savedItem.toJson()]),
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final item = container.read(inventoryProvider).single;

        expect(item.freshnessPercent, closeTo(1 / 7, 0.001));
        // Expiring tomorrow is within the urgent window.
        expect(item.state, FreshnessState.urgent);
        expect(item.expiryLabel, '明天过期');
      },
    );

    test(
      'preserves original added time when updating an inventory item',
      () async {
        final addedAt = DateTime.utc(2026, 4, 26, 8);
        final original = _ingredient('牛奶').copyWith(addedAt: addedAt);
        SharedPreferences.setMockInitialValues({
          'inventory_items': json.encode([original.toJson()]),
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await container
            .read(inventoryProvider.notifier)
            .update(0, _ingredient('酸奶'));

        final item = container.read(inventoryProvider).single;
        expect(item.name, '酸奶');
        expect(item.addedAt, addedAt);
      },
    );

    test(
      'records concurrent duplicate adds without losing history count',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({}),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final first = container
            .read(inventoryProvider.notifier)
            .add(_ingredient('牛奶'));
        final second = container
            .read(inventoryProvider.notifier)
            .add(_ingredient('牛奶'));
        await Future.wait([first, second]);

        final history = json.decode(prefs.getString('add_history')!);
        expect(history['牛奶']['count'], 2);

        // Both items must end up persisted, in the order they were enqueued.
        final inventoryState = container.read(inventoryProvider);
        expect(inventoryState, hasLength(2));
        expect(inventoryState.map((item) => item.name), ['牛奶', '牛奶']);

        final savedInventory =
            json.decode(prefs.getString('inventory_items')!) as List<dynamic>;
        expect(savedInventory, hasLength(2));
        expect(savedInventory.map((row) => (row as Map)['name']).toList(), [
          '牛奶',
          '牛奶',
        ]);
      },
    );

    test(
      'ignores malformed frequent item fields without hiding valid items',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[]',
          'add_history': json.encode({
            '坏数据': {'count': 4, 'category': 123, 'storage': 456, 'unit': false},
            '鸡蛋': {
              'count': 2,
              'category': '蛋类',
              'storage': 'fridge',
              'unit': '个',
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final frequentItems = container.read(frequentItemsProvider);

        expect(frequentItems.map((item) => item.name), contains('鸡蛋'));
      },
    );

    test(
      'inserts inventory item at the requested index without recording add history',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': json.encode([
            _ingredient('牛奶').toJson(),
            _ingredient('番茄').toJson(),
          ]),
          'add_history': json.encode({
            '鸡蛋': {
              'count': 1,
              'category': '蛋类',
              'storage': 'fridge',
              'unit': '个',
            },
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await container
            .read(inventoryProvider.notifier)
            .insertAt(1, _ingredient('鸡蛋'));

        expect(container.read(inventoryProvider).map((item) => item.name), [
          '牛奶',
          '鸡蛋',
          '番茄',
        ]);
        final history = json.decode(prefs.getString('add_history')!);
        expect(history['鸡蛋']['count'], 1);
      },
    );
  });

  group('InventoryNotifier.update + remove edge cases', () {
    test('update with negative index leaves state unchanged', () async {
      final container = await _containerWithInventory([_ingredient('番茄')]);
      addTearDown(container.dispose);

      await container
          .read(inventoryProvider.notifier)
          .update(-1, _ingredient('苹果'));
      expect(container.read(inventoryProvider).map((i) => i.name), ['番茄']);
    });

    test('update with out-of-bounds index leaves state unchanged', () async {
      final container = await _containerWithInventory([_ingredient('番茄')]);
      addTearDown(container.dispose);

      await container
          .read(inventoryProvider.notifier)
          .update(99, _ingredient('苹果'));
      expect(container.read(inventoryProvider).map((i) => i.name), ['番茄']);
    });

    test('remove with negative index leaves state unchanged', () async {
      final container = await _containerWithInventory([_ingredient('番茄')]);
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).remove(-1);
      expect(container.read(inventoryProvider).map((i) => i.name), ['番茄']);
    });

    test('remove with out-of-bounds index leaves state unchanged', () async {
      final container = await _containerWithInventory([_ingredient('番茄')]);
      addTearDown(container.dispose);

      await container.read(inventoryProvider.notifier).remove(99);
      expect(container.read(inventoryProvider).map((i) => i.name), ['番茄']);
    });
  });

  group('frequentItemsProvider caps and filters', () {
    test('excludes items with count < 2', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'add_history': json.encode({
          '常用': {
            'count': 3,
            'category': '其他',
            'storage': 'fridge',
            'unit': '个',
          },
          '单次': {
            'count': 1,
            'category': '其他',
            'storage': 'fridge',
            'unit': '个',
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final frequent = container.read(frequentItemsProvider);
      expect(frequent.map((i) => i.name), contains('常用'));
      expect(frequent.map((i) => i.name), isNot(contains('单次')));
    });

    test('caps result at 6 items even with more qualifying entries', () async {
      final history = {
        for (var i = 0; i < 8; i++)
          '食材$i': {
            'count': 2,
            'category': '其他',
            'storage': 'fridge',
            'unit': '个',
          },
      };
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'add_history': json.encode(history),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final frequent = container.read(frequentItemsProvider);
      expect(frequent.length, lessThanOrEqualTo(6));
    });
  });

  group('expiryLabelFor', () {
    test('formats expiry labels consistently', () {
      final now = DateTime(2026, 4, 27, 14);

      expect(expiryLabelFor(DateTime(2026, 4, 26), now: now), '已过期1天');
      expect(expiryLabelFor(DateTime(2026, 4, 27), now: now), '今天过期');
      expect(expiryLabelFor(DateTime(2026, 4, 28), now: now), '明天过期');
      expect(expiryLabelFor(DateTime(2026, 5, 1), now: now), '4天后过期');
    });
  });

  group('ShoppingNotifier.load', () {
    test('deduplicates persisted item names', () async {
      SharedPreferences.setMockInitialValues({
        'shopping_items': json.encode([
          _shoppingItem('si_1', '牛奶').toJson(),
          _shoppingItem('si_2', '牛奶').toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(shoppingProvider).map((item) => item.name), ['牛奶']);
    });

    test(
      'loads valid shopping rows when persisted list has bad rows',
      () async {
        SharedPreferences.setMockInitialValues({
          'shopping_items': json.encode([
            _shoppingItem('si_1', '牛奶').toJson(),
            42,
            {'id': 'si_2', 'name': '鸡蛋'},
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(shoppingProvider).map((item) => item.name), [
          '牛奶',
          '鸡蛋',
        ]);
      },
    );

    test('assigns distinct ids when persisted items reuse an id', () async {
      SharedPreferences.setMockInitialValues({
        'shopping_items': json.encode([
          _shoppingItem('si_same', '牛奶').toJson(),
          _shoppingItem('si_same', '鸡蛋').toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final items = container.read(shoppingProvider);
      expect(items.map((item) => item.name), ['牛奶', '鸡蛋']);
      expect(items.map((item) => item.id).toSet(), hasLength(2));
    });
  });

  group('ShoppingNotifier.add', () {
    test('ignores duplicate item names', () async {
      SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container
          .read(shoppingProvider.notifier)
          .add(_shoppingItem('si_1', '牛奶'));
      await container
          .read(shoppingProvider.notifier)
          .add(_shoppingItem('si_2', '牛奶'));

      final items = container.read(shoppingProvider);
      expect(items.map((item) => item.name), ['牛奶']);

      final savedItems = json.decode(prefs.getString('shopping_items')!);
      expect(savedItems, hasLength(1));
    });

    test(
      'keeps different items independent when added with the same id',
      () async {
        SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        await container
            .read(shoppingProvider.notifier)
            .add(_shoppingItem('si_same', '牛奶'));
        await container
            .read(shoppingProvider.notifier)
            .add(_shoppingItem('si_same', '鸡蛋'));

        final items = container.read(shoppingProvider);
        expect(items.map((item) => item.name), ['牛奶', '鸡蛋']);
        expect(items.map((item) => item.id).toSet(), hasLength(2));

        await container
            .read(shoppingProvider.notifier)
            .toggleCheck(items.first.id);

        expect(container.read(shoppingProvider).map((item) => item.isChecked), [
          true,
          false,
        ]);
      },
    );
  });

  group('ShoppingNotifier.remove', () {
    test('remove with unknown id does not crash or change state', () async {
      SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container
          .read(shoppingProvider.notifier)
          .add(_shoppingItem('si_1', '牛奶'));
      await container.read(shoppingProvider.notifier).remove('si_nonexistent');

      expect(container.read(shoppingProvider).map((i) => i.name), ['牛奶']);
    });

    test('toggleCheck toggles checked state persistently', () async {
      SharedPreferences.setMockInitialValues({
        'shopping_items': json.encode([_shoppingItem('si_1', '苹果').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(shoppingProvider.notifier).toggleCheck('si_1');
      expect(container.read(shoppingProvider).single.isChecked, isTrue);

      await container.read(shoppingProvider.notifier).toggleCheck('si_1');
      expect(container.read(shoppingProvider).single.isChecked, isFalse);
    });
  });

  group('ShoppingNotifier.addFromSuggestion', () {
    test('ignores duplicate suggestions by name', () async {
      SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(shoppingProvider.notifier).addFromSuggestion('鸡蛋');
      await container.read(shoppingProvider.notifier).addFromSuggestion('鸡蛋');

      expect(container.read(shoppingProvider).map((item) => item.name), ['鸡蛋']);
    });

    test('returns false for blank input', () async {
      SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final added = await container
          .read(shoppingProvider.notifier)
          .addFromSuggestion('   ');
      expect(added, isFalse);
      expect(container.read(shoppingProvider), isEmpty);
    });

    test('uses stable food knowledge categories for suggestions', () async {
      SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(shoppingProvider.notifier).addFromSuggestion('番茄');
      await container.read(shoppingProvider.notifier).addFromSuggestion('番茄酱');

      final categoriesByName = {
        for (final item in container.read(shoppingProvider))
          item.name: item.category,
      };

      expect(categoriesByName['番茄'], FoodCategories.freshProduce);
      expect(categoriesByName['番茄酱'], FoodCategories.other);
    });
  });

  group('storage areas', () {
    test('exposes fridge, freezer and pantry storage areas', () async {
      final container = await _containerWithInventory([]);
      addTearDown(container.dispose);

      final areas = container.read(storageAreasProvider);

      expect(areas.map((area) => area.icon), [
        IconType.fridge,
        IconType.freezer,
        IconType.pantry,
      ]);
      expect(areas.map((area) => area.name), contains('冷冻室'));
    });

    test('preserves legacy freezer storage as a freezer area', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([
          {
            'name': '旧冷冻食材',
            'quantity': '1',
            'unit': '份',
            'imageUrl': '',
            'freshnessPercent': 1.0,
            'state': 'fresh',
            'storage': 'freezer',
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final item = container.read(inventoryProvider).single;

      expect(item.storage, IconType.freezer);
    });
  });

  group('inventory filters', () {
    test('not fresh filter includes expiring soon and expired items', () async {
      final freshItem = _ingredient('黄瓜');
      final expiringItem = _ingredient(
        '牛奶',
        state: FreshnessState.expiringSoon,
      );
      final expiredItem = _ingredient('面包', state: FreshnessState.expired);
      final container = await _containerWithInventory([
        freshItem,
        expiringItem,
        expiredItem,
      ]);
      addTearDown(container.dispose);

      container.read(selectedCategoryProvider.notifier).state = '不新鲜';

      expect(
        container.read(filteredByCategoryProvider).map((item) => item.name),
        ['牛奶', '面包'],
      );
    });
  });

  group('recommendedRecipesProvider', () {
    test('returns empty when inventory is empty', () async {
      final container = await _containerWithInventory([]);
      addTearDown(container.dispose);

      expect(container.read(recommendedRecipesProvider), isEmpty);
    });

    test('filters out recipes without matched ingredients', () async {
      final recipes = [
        _recipe('match', '番茄炒蛋', ['鸡蛋', '番茄']),
        _recipe('miss', '红烧牛肉', ['牛肉']),
      ];
      final container = await _containerWithInventory([
        _ingredient('鸡蛋'),
      ], recipes: recipes);
      addTearDown(container.dispose);
      await container.read(recipesProvider.future);

      final recommended = container.read(recommendedRecipesProvider);

      expect(recommended.map((recipe) => recipe.id), ['match']);
    });

    test('includes matched custom recipes in recommendations', () async {
      final customRecipe = _recipe('custom-match', '我的鸡蛋饼', ['鸡蛋']);
      final container = await _containerWithInventory(
        [_ingredient('鸡蛋')],
        recipes: const [],
        customRecipes: [customRecipe],
      );
      addTearDown(container.dispose);
      await container.read(recipesProvider.future);

      final recommended = container.read(recommendedRecipesProvider);

      expect(recommended.map((recipe) => recipe.id), ['custom-match']);
    });

    test('does not match recipes from blank inventory names', () async {
      final recipes = [
        _recipe('match', '番茄炒蛋', ['鸡蛋']),
      ];
      final container = await _containerWithInventory([
        _ingredient('   '),
      ], recipes: recipes);
      addTearDown(container.dispose);
      await container.read(recipesProvider.future);

      expect(container.read(recommendedRecipesProvider), isEmpty);
      expect(
        matchedIngredientCount(
          container.read(inventoryProvider),
          recipes.single,
        ),
        0,
      );
    });

    test(
      'matchedIngredientCount returns zero for empty inventory and recipe',
      () {
        expect(
          matchedIngredientCount(const [], _recipe('empty', '空菜谱', const [])),
          0,
        );
      },
    );
  });

  group('recipesProvider cache', () {
    test('returns no recipes without inventory terms', () async {
      SharedPreferences.setMockInitialValues({'inventory_items': '[]'});
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeMealDbApi(
        onSearch: (_) => throw StateError('network should not be called'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mealDbApiProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final recipes = await container.read(recipesProvider.future);

      expect(recipes, isEmpty);
      expect(client.calls, 0);
    });

    test('uses cached TheMealDB recipes without calling the client', () async {
      final cachedRecipe = _recipe('mealdb_cached', '缓存番茄菜谱', ['tomato']);
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([_ingredient('番茄').toJson()]),
        recipeDetailsCacheStorageKey: json.encode({
          recipeSearchCacheKeyFor('tomato'): [cachedRecipe.toJson()],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeMealDbApi(
        onSearch: (_) => throw StateError('network should not be called'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mealDbApiProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final recipes = await container.read(recipesProvider.future);

      expect(recipes.map((recipe) => recipe.id), contains('mealdb_cached'));
      expect(client.calls, 0);
    });

    test('saves TheMealDB recipes after a cache miss', () async {
      final fetchedRecipe = _recipe('mealdb_fetched', '联网番茄菜谱', ['tomato']);
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([_ingredient('番茄').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeMealDbApi(onSearch: (_) async => [fetchedRecipe]);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mealDbApiProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final recipes = await container.read(recipesProvider.future);

      expect(recipes.map((recipe) => recipe.id), contains('mealdb_fetched'));
      expect(client.calls, 1);

      final saved = json.decode(prefs.getString(recipeDetailsCacheStorageKey)!);
      expect(
        saved[recipeSearchCacheKeyFor('tomato')].single['id'],
        'mealdb_fetched',
      );
    });

    test(
      'does not fall back to demo recipes when TheMealDB client throws',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': json.encode([_ingredient('番茄').toJson()]),
        });
        final prefs = await SharedPreferences.getInstance();
        final client = _FakeMealDbApi(
          onSearch: (_) => throw StateError('service unavailable'),
        );
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mealDbApiProvider.overrideWithValue(client),
          ],
        );
        addTearDown(container.dispose);

        final recipes = await container.read(recipesProvider.future);

        expect(client.calls, 1);
        expect(recipes, isEmpty);
      },
    );

    test('recipesFetchProvider flags fetchFailed when every term fails', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': json.encode([_ingredient('番茄').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeMealDbApi(
        onSearch: (_) => throw StateError('service unavailable'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mealDbApiProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(recipesFetchProvider.future);

      expect(result.recipes, isEmpty);
      expect(result.fetchFailed, isTrue);
    });
  });
}

Future<ProviderContainer> _containerWithInventory(
  List<Ingredient> inventory, {
  List<Recipe>? recipes,
  List<Recipe>? customRecipes,
}) async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': json.encode(
      inventory.map((item) => item.toJson()).toList(),
    ),
    if (customRecipes != null)
      customRecipesStorageKey: json.encode(
        customRecipes.map((recipe) => recipe.toJson()).toList(),
      ),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (recipes != null) recipesProvider.overrideWith((ref) async => recipes),
    ],
  );
}

Ingredient _ingredient(
  String name, {
  FreshnessState state = FreshnessState.fresh,
}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '个',
    imageUrl: '',
    freshnessPercent: 1,
    state: state,
    category: '测试',
    storage: IconType.fridge,
  );
}

Recipe _recipe(String id, String name, List<String> ingredients) {
  return Recipe(
    id: id,
    name: name,
    category: '测试',
    difficulty: 1,
    cookingMinutes: 10,
    description: '',
    ingredients: ingredients
        .map((ingredient) => RecipeIngredient(name: ingredient, amount: '1'))
        .toList(),
    steps: const [],
  );
}

class _FakeMealDbApi implements MealDbApi {
  _FakeMealDbApi({required this.onSearch});

  final Future<List<Recipe>> Function(String term) onSearch;
  int calls = 0;

  @override
  Future<List<Recipe>> searchByName(String term) {
    calls++;
    return onSearch(term);
  }
}

ShoppingItem _shoppingItem(String id, String name) {
  return ShoppingItem(id: id, name: name, detail: '', category: '其他');
}
