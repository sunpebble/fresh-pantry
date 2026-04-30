import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recipe.dart';
import '../models/ingredient.dart';
import '../data/mock_data.dart';
import '../data/food_knowledge.dart';
import '../services/themealdb_service.dart';
import 'custom_recipe_provider.dart';
import 'inventory_provider.dart';

Set<String> _inventoryNameSet(Iterable<Ingredient> inventory) {
  return inventory
      .map((item) => item.name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
}

bool _recipeIngredientMatchesInventory(
  RecipeIngredient ingredient,
  Set<String> inventoryNames,
) {
  final ingredientName = ingredient.name.trim().toLowerCase();
  if (ingredientName.isEmpty) return false;

  return inventoryNames.any(
    (name) => name.contains(ingredientName) || ingredientName.contains(name),
  );
}

int _matchedIngredientCountForNames(Set<String> inventoryNames, Recipe recipe) {
  if (inventoryNames.isEmpty || recipe.ingredients.isEmpty) return 0;

  return recipe.ingredients
      .where(
        (ingredient) =>
            _recipeIngredientMatchesInventory(ingredient, inventoryNames),
      )
      .length;
}

/// All available recipes — mock recipes + TheMealDB results
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final inventory = ref.watch(inventoryProvider);

  // Always start with mock Chinese recipes
  final allRecipes = List<Recipe>.from(MockData.recipes);
  final seenIds = allRecipes.map((r) => r.id).toSet();

  if (inventory.isEmpty) return allRecipes;

  // Translate Chinese ingredient names to English for TheMealDB search
  final englishTerms =
      inventory
          .take(3)
          .map((i) => FoodKnowledge.englishName(i.name))
          .whereType<String>()
          .toSet() // deduplicate (e.g. multiple egg items)
          .toList();

  for (final term in englishTerms) {
    try {
      final results = await TheMealDbService.searchByName(term);
      for (final recipe in results) {
        if (seenIds.add(recipe.id)) {
          allRecipes.add(recipe);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching recipes for "$term": $e');
      }
    }
  }

  return allRecipes;
});

/// Recipes that can be made with current inventory ingredients
final recommendedRecipesProvider = Provider<List<Recipe>>((ref) {
  final recipesAsync = ref.watch(recipesProvider);
  final customRecipes = ref.watch(customRecipesProvider);
  final inventory = ref.watch(inventoryProvider);

  final baseRecipes = recipesAsync.when(
    data: (data) => data,
    loading: () => List<Recipe>.from(MockData.recipes),
    error: (_, _) => List<Recipe>.from(MockData.recipes),
  );
  final recipes = List<Recipe>.from(baseRecipes);
  final seenIds = recipes.map((recipe) => recipe.id).toSet();
  for (final recipe in customRecipes) {
    if (seenIds.add(recipe.id)) {
      recipes.add(recipe);
    }
  }

  if (inventory.isEmpty) return [];

  final inventoryNames = _inventoryNameSet(inventory);

  // Score each recipe by how many ingredients are available
  final scored =
      recipes.map((recipe) {
        final matched = _matchedIngredientCountForNames(inventoryNames, recipe);
        if (matched == 0 || recipe.ingredients.isEmpty) {
          return (recipe: recipe, score: 0.0);
        }
        return (recipe: recipe, score: matched / recipe.ingredients.length);
      }).toList();

  // Sort by match score descending
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.where((e) => e.score > 0).map((e) => e.recipe).toList();
});

/// Count of matching inventory items for a recipe
int matchedIngredientCount(List<Ingredient> inventory, Recipe recipe) {
  return _matchedIngredientCountForNames(_inventoryNameSet(inventory), recipe);
}
