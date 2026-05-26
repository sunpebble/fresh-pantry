import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'returns cached food details without calling the network client',
    () async {
      final ingredient = _ingredient('番茄');
      final cached = FoodDetails(
        displayName: '番茄',
        description: '缓存中的番茄详情',
        imageUrl: 'https://example.com/tomato.jpg',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
        source: 'Open Food Facts',
        fetchedAt: DateTime.utc(2026, 5, 1),
      );
      SharedPreferences.setMockInitialValues({
        foodDetailsCacheStorageKey: jsonEncode({
          foodDetailsCacheKeyFor(ingredient): cached.toJson(),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeFoodDetailsClient(lookupResult: null);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          foodDetailsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final details = await container.read(
        foodDetailsProvider(ingredient).future,
      );

      expect(details.description, '缓存中的番茄详情');
      expect(client.calls, 0);
    },
  );

  test('fetches and saves food details when the cache is empty', () async {
    final ingredient = _ingredient('牛奶').copyWith(barcode: '6900000000001');
    final fetched = FoodDetails(
      displayName: '有机牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl: 'https://example.com/milk.jpg',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = _FakeFoodDetailsClient(lookupResult: fetched);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        foodDetailsClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);

    final details = await container.read(
      foodDetailsProvider(ingredient).future,
    );

    expect(details.displayName, '有机牛奶');
    expect(client.calls, 1);

    final saved = jsonDecode(prefs.getString(foodDetailsCacheStorageKey)!);
    expect(saved[foodDetailsCacheKeyFor(ingredient)]['displayName'], '有机牛奶');
  });

  test(
    'falls back to local food knowledge when external lookup has no result',
    () async {
      final ingredient = _ingredient('鸡蛋');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeFoodDetailsClient(lookupResult: null);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          foodDetailsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final details = await container.read(
        foodDetailsProvider(ingredient).future,
      );

      expect(details.displayName, '鸡蛋');
      expect(details.category, FoodCategories.dairyAndEggs);
      expect(details.storage, IconType.fridge);
      expect(details.shelfLifeDays, 30);
      expect(details.source, '本地食材知识库');
      expect(details.imageUrl, contains('/images/ingredients/egg.png'));
    },
  );

  test(
    'falls back to local food knowledge when external lookup throws',
    () async {
      final ingredient = _ingredient('鸡蛋');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeFoodDetailsClient(
        lookupResult: null,
        lookupError: StateError('network down'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          foodDetailsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final details = await container.read(
        foodDetailsProvider(ingredient).future,
      );

      expect(details.displayName, '鸡蛋');
      expect(details.source, '本地食材知识库');
      expect(client.calls, 1);
    },
  );

  test(
    'retries external lookup when the cached value is local fallback',
    () async {
      final ingredient = _ingredient('牛奶');
      final cached = FoodDetails(
        displayName: '牛奶',
        description: '建议存放在冰箱，约 7 天内食用。',
        imageUrl: 'https://www.themealdb.com/images/ingredients/milk.png',
        category: FoodCategories.dairyAndEggs,
        storage: IconType.fridge,
        shelfLifeDays: 7,
        source: '本地食材知识库',
        fetchedAt: DateTime.utc(2026, 5, 1),
      );
      final fetched = FoodDetails(
        displayName: '伊利牛奶',
        description: 'Open Food Facts 返回的牛奶详情',
        imageUrl: 'https://example.com/milk.jpg',
        category: FoodCategories.dairyAndEggs,
        storage: IconType.fridge,
        shelfLifeDays: 7,
        source: 'Open Food Facts',
        fetchedAt: DateTime.utc(2026, 5, 1),
      );
      SharedPreferences.setMockInitialValues({
        foodDetailsCacheStorageKey: jsonEncode({
          foodDetailsCacheKeyFor(ingredient): cached.toJson(),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final client = _FakeFoodDetailsClient(lookupResult: fetched);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          foodDetailsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final details = await container.read(
        foodDetailsProvider(ingredient).future,
      );

      expect(details.displayName, '伊利牛奶');
      expect(details.source, 'Open Food Facts');
      expect(client.calls, 1);

      final saved = jsonDecode(prefs.getString(foodDetailsCacheStorageKey)!);
      expect(
        saved[foodDetailsCacheKeyFor(ingredient)]['source'],
        'Open Food Facts',
      );
    },
  );

  test('retries external lookup for stale cache entries', () async {
    final ingredient = _ingredient('牛奶');
    final legacyCache =
        FoodDetails(
            displayName: '臻浓牛奶',
            description: 'Open Food Facts 记录的乳品蛋类食品。',
            imageUrl: 'https://example.com/placeholder.jpg',
            category: FoodCategories.dairyAndEggs,
            storage: IconType.fridge,
            shelfLifeDays: 7,
            source: 'Open Food Facts',
            fetchedAt: DateTime.utc(2026, 5, 1),
          ).toJson()
          ..['cacheVersion'] = 3;
    final fetched = FoodDetails(
      displayName: '牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl: 'https://example.com/real-milk.jpg',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );
    SharedPreferences.setMockInitialValues({
      foodDetailsCacheStorageKey: jsonEncode({
        foodDetailsCacheKeyFor(ingredient): legacyCache,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final client = _FakeFoodDetailsClient(lookupResult: fetched);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        foodDetailsClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);

    final details = await container.read(
      foodDetailsProvider(ingredient).future,
    );

    expect(details.displayName, '牛奶');
    expect(details.imageUrl, 'https://example.com/real-milk.jpg');
    expect(client.calls, 1);
  });
}

class _FakeFoodDetailsClient implements FoodDetailsClient {
  _FakeFoodDetailsClient({required this.lookupResult, this.lookupError});

  final FoodDetails? lookupResult;
  final Object? lookupError;
  int calls = 0;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) async {
    calls++;
    final error = lookupError;
    if (error != null) throw error;
    return lookupResult;
  }
}

Ingredient _ingredient(String name) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: FoodCategories.other,
    storage: IconType.fridge,
    expiryLabel: '新鲜',
  );
}
