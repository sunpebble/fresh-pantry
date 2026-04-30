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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

        final add = container
            .read(inventoryProvider.notifier)
            .add(_ingredient('鸡蛋'));
        await Future.microtask(() {});
        await add;

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
      expect(item.state, FreshnessState.expiringSoon);
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
        expect(item.state, FreshnessState.expiringSoon);
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
    test('exposes only fridge and pantry storage areas', () async {
      final container = await _containerWithInventory([]);
      addTearDown(container.dispose);

      final areas = container.read(storageAreasProvider);

      expect(areas.map((area) => area.icon), [
        IconType.fridge,
        IconType.pantry,
      ]);
      expect(areas.map((area) => area.name), isNot(contains('冷冻室')));
    });

    test('migrates legacy freezer storage to fridge', () async {
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

      expect(item.storage, IconType.fridge);
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
    ingredients:
        ingredients
            .map(
              (ingredient) => RecipeIngredient(name: ingredient, amount: '1'),
            )
            .toList(),
    steps: const [],
  );
}

ShoppingItem _shoppingItem(String id, String name) {
  return ShoppingItem(id: id, name: name, detail: '', category: '其他');
}
