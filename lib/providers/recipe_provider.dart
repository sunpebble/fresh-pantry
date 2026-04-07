import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recipe.dart';
import '../models/ingredient.dart';
import '../data/mock_data.dart';
import '../data/food_knowledge.dart';
import '../services/themealdb_service.dart';
import 'inventory_provider.dart';

/// All available recipes — mock recipes + TheMealDB results
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final inventory = ref.watch(inventoryProvider);

  // Always start with mock Chinese recipes
  final allRecipes = List<Recipe>.from(MockData.recipes);
  final seenIds = allRecipes.map((r) => r.id).toSet();

  if (inventory.isEmpty) return allRecipes;

  // Translate Chinese ingredient names to English for TheMealDB search
  final englishTerms = inventory
      .take(3)
      .map((i) => FoodKnowledge.englishName(i.name))
      .whereType<String>()
      .toSet() // deduplicate (e.g. multiple egg items)
      .toList();

  for (final term in englishTerms) {
    final results = await TheMealDbService.searchByName(term);
    for (final recipe in results) {
      if (seenIds.add(recipe.id)) {
        allRecipes.add(recipe);
      }
    }
  }

  return allRecipes;
});

/// Recipes that can be made with current inventory ingredients
final recommendedRecipesProvider = Provider<List<Recipe>>((ref) {
  final recipesAsync = ref.watch(recipesProvider);
  final inventory = ref.watch(inventoryProvider);

  final recipes = recipesAsync.when(
    data: (data) => data,
    loading: () => List<Recipe>.from(MockData.recipes),
    error: (_, _) => List<Recipe>.from(MockData.recipes),
  );

  final inventoryNames = inventory.map((i) => i.name.toLowerCase()).toSet();

  // Score each recipe by how many ingredients are available
  final scored = recipes.map((recipe) {
    final matched = recipe.ingredients
        .where(
          (ing) => inventoryNames.any(
            (name) =>
                name.contains(ing.name.toLowerCase()) ||
                ing.name.toLowerCase().contains(name),
          ),
        )
        .length;
    return (recipe: recipe, score: matched / recipe.ingredients.length);
  }).toList();

  // Sort by match score descending
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.map((e) => e.recipe).toList();
});

/// Count of matching inventory items for a recipe
int matchedIngredientCount(List<Ingredient> inventory, Recipe recipe) {
  final inventoryNames = inventory.map((i) => i.name.toLowerCase()).toSet();
  return recipe.ingredients
      .where(
        (ing) => inventoryNames.any(
          (name) =>
              name.contains(ing.name.toLowerCase()) ||
              ing.name.toLowerCase().contains(name),
        ),
      )
      .length;
}
