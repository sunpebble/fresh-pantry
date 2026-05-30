import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing({
  required String name,
  FreshnessState state = FreshnessState.fresh,
}) => Ingredient(
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: state == FreshnessState.fresh ? 1.0 : 0.2,
  state: state,
  category: FoodCategories.other,
  storage: IconType.fridge,
);

Recipe _recipe(String id, List<String> ings) => Recipe(
  id: id,
  name: id,
  category: '中餐',
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients:
      ings
          .map((n) => RecipeIngredient(name: n, quantity: '1', unit: '个'))
          .toList(),
  steps: const [],
);

Future<ProviderContainer> _container({
  required List<Ingredient> inventory,
  required List<Recipe> recipes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      inventorySeedProvider.overrideWithValue(inventory),
      recipesProvider.overrideWith((ref) => Future.value(recipes)),
    ],
  );
  await c.read(recipesProvider.future);
  return c;
}

void main() {
  test('returns null when no expiring items', () async {
    final c = await _container(
      inventory: [_ing(name: '苹果')],
      recipes: [
        _recipe('a', ['苹果']),
      ],
    );
    expect(c.read(expiringFallbackRecipeProvider), isNull);
  });

  test('returns recipe covering most expiring items', () async {
    final inventory = [
      _ing(name: '番茄', state: FreshnessState.expiringSoon),
      _ing(name: '鸡蛋', state: FreshnessState.expiringSoon),
      _ing(name: '黄瓜', state: FreshnessState.fresh),
    ];
    final recipes = [
      _recipe('a', ['番茄', '鸡蛋']),
      _recipe('b', ['番茄', '黄瓜']),
      _recipe('c', ['黄瓜']),
    ];
    final c = await _container(inventory: inventory, recipes: recipes);
    final result = c.read(expiringFallbackRecipeProvider);
    expect(result, isNotNull);
    expect(result!.recipe.id, 'a');
    expect(result.coveredExpiringNames, {'番茄', '鸡蛋'});
  });

  test('returns null when no recipe covers any expiring item', () async {
    final inventory = [_ing(name: '番茄', state: FreshnessState.expiringSoon)];
    final recipes = [
      _recipe('a', ['苹果']),
    ];
    final c = await _container(inventory: inventory, recipes: recipes);
    expect(c.read(expiringFallbackRecipeProvider), isNull);
  });
}
