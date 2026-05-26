import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Recipe _recipe(String id, String name, List<String> ingredientNames) => Recipe(
  id: id,
  name: name,
  category: '中餐',
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients:
      ingredientNames
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
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(inventory),
      recipesProvider.overrideWith((ref) => Future.value(recipes)),
    ],
  );
}

void main() {
  test(
    'recipe using an expiringSoon ingredient ranks above an equal-match fresh one',
    () async {
      final inventory = [
        _ing(name: '番茄', state: FreshnessState.expiringSoon),
        _ing(name: '鸡蛋', state: FreshnessState.fresh),
        _ing(name: '黄瓜', state: FreshnessState.fresh),
      ];
      // Put the non-expiring recipe FIRST so that without the boost, a stable sort
      // would keep 'b' ahead of 'a' (both score 1.0 matched/total). The boost
      // must push 'a' (uses expiringSoon 番茄) past 'b'.
      final recipes = [
        _recipe('b', '黄瓜炒蛋', [
          '黄瓜',
          '鸡蛋',
        ]), // doesn't use expiring — listed first
        _recipe('a', '番茄炒蛋', ['番茄', '鸡蛋']), // uses expiring — listed second
      ];
      final c = await _container(inventory: inventory, recipes: recipes);
      addTearDown(c.dispose);
      // Wait for the async recipesProvider to resolve.
      await c.read(recipesProvider.future);
      final ranked = c.read(recommendedRecipesProvider);
      expect(
        ranked.first.id,
        'a',
        reason: 'expiringSoon-boost should put 番茄炒蛋 first',
      );
    },
  );
}
