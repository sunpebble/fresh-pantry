import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../storage/local_recipe_repository.dart';
import 'custom_recipe_provider.dart';
import 'inventory_provider.dart';

final localRecipeRepositoryProvider = Provider<LocalRecipeRepository>(
  (ref) => LocalRecipeRepository(),
);

Set<String> inventoryNameSet(Iterable<Ingredient> inventory) {
  return inventory
      .map((item) => item.name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
}

bool recipeIngredientMatchesInventory(
  RecipeIngredient ingredient,
  Set<String> inventoryNames,
) {
  final ingredientName = ingredient.name.trim().toLowerCase();
  if (ingredientName.isEmpty) return false;

  return inventoryNames.any(
    (name) => name.contains(ingredientName) || ingredientName.contains(name),
  );
}

int matchedIngredientCountForNames(Set<String> inventoryNames, Recipe recipe) {
  if (inventoryNames.isEmpty || recipe.ingredients.isEmpty) return 0;

  return recipe.ingredients
      .where(
        (ingredient) =>
            recipeIngredientMatchesInventory(ingredient, inventoryNames),
      )
      .length;
}

List<RecipeIngredient> missingRecipeIngredientsForNames(
  Set<String> inventoryNames,
  Recipe recipe,
) {
  return recipe.ingredients
      .where(
        (ingredient) =>
            !recipeIngredientMatchesInventory(ingredient, inventoryNames),
      )
      .toList();
}

/// Explore-tab data source: loads ALL local HowToCook (Chinese) recipes.
///
/// Returns `({recipes, fetchFailed})` to keep the explore tab's existing
/// retry UI: on a missing/corrupt asset, recipes is empty and fetchFailed is
/// true. Inventory-based match ranking is handled by [recommendedRecipesProvider],
/// which is agnostic to the data source.
final recipesFetchProvider =
    FutureProvider<({List<Recipe> recipes, bool fetchFailed})>((ref) async {
      final repo = ref.watch(localRecipeRepositoryProvider);
      try {
        final recipes = await repo.loadAll();
        return (recipes: recipes, fetchFailed: false);
      } catch (e, stack) {
        if (kDebugMode) {
          debugPrint('Local recipe load failed: $e\n$stack');
        }
        return (recipes: <Recipe>[], fetchFailed: true);
      }
    });

/// Recipes discovered from the user's current inventory.
///
/// Derives from [recipesFetchProvider] and deliberately resolves to an empty
/// list (never throws) on fetch failure, so consumers like
/// [recommendedRecipesProvider] degrade gracefully. Watch
/// [recipesFetchProvider] when you also need to know whether the fetch failed.
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final result = await ref.watch(recipesFetchProvider.future);
  return result.recipes;
});

/// Stable string signature of the lowercased inventory name set. Used as the
/// `.select` key for [recommendedRecipesProvider] so Riverpod's `==`
/// comparison can short-circuit rebuilds when names are unchanged. A raw
/// `Set<String>` returned from select would not deduplicate, since `Set` does
/// not override `==` by content.
String inventoryNamesSignature(Iterable<Ingredient> inventory) {
  final names = inventoryNameSet(inventory).toList()..sort();
  return names.join(' ');
}

/// Recipes that can be made with current inventory ingredients.
///
/// Uses `.select` so this provider only re-runs when inventory **names**
/// change. Freshness/expiry/quantity updates do not invalidate. The selector
/// returns a stable string key; the body re-derives the name set on each
/// (rare) rebuild, which is cheap (linear over the inventory).
final recommendedRecipesProvider = Provider<List<Recipe>>((ref) {
  // Watching the signature alone subscribes us; reading the full inventory
  // afterwards does not add a dependency, but supplies the source for the
  // name set used by scoring.
  ref.watch(inventoryProvider.select(inventoryNamesSignature));
  final inventoryNames = inventoryNameSet(ref.read(inventoryProvider));
  final recipesAsync = ref.watch(recipesProvider);
  final customRecipes = ref.watch(customRecipesProvider);

  final baseRecipes = recipesAsync.when(
    data: (data) => data,
    loading: () => const <Recipe>[],
    error: (_, _) => const <Recipe>[],
  );
  final recipes = List<Recipe>.from(baseRecipes);
  final seenIds = recipes.map((recipe) => recipe.id).toSet();
  for (final recipe in customRecipes) {
    if (seenIds.add(recipe.id)) {
      recipes.add(recipe);
    }
  }

  if (inventoryNames.isEmpty) return [];

  // Build a set of normalised names for expiring/expired inventory items so
  // that recipes using them can receive a ranking boost.
  final expiringNameSet = ref
      .read(inventoryProvider)
      .where(isNotFreshIngredient)
      .map((i) => i.name.trim().toLowerCase())
      .toSet();

  // Score each recipe by how many ingredients are available, with a +0.5
  // boost when any ingredient is expiring/expired so those recipes surface
  // first and help the user use up perishables.
  final scored = recipes.map((recipe) {
    final matched = matchedIngredientCountForNames(inventoryNames, recipe);
    if (matched == 0 || recipe.ingredients.isEmpty) {
      return (recipe: recipe, score: 0.0);
    }
    final base = matched / recipe.ingredients.length;
    final usesExpiring = recipe.ingredients.any(
      (ri) => expiringNameSet.contains(ri.name.trim().toLowerCase()),
    );
    final boost = usesExpiring ? 0.5 : 0.0;
    return (recipe: recipe, score: base + boost);
  }).toList();

  // Sort by match score descending
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.where((e) => e.score > 0).map((e) => e.recipe).toList();
});

/// Count of matching inventory items for a recipe
int matchedIngredientCount(List<Ingredient> inventory, Recipe recipe) {
  return matchedIngredientCountForNames(inventoryNameSet(inventory), recipe);
}

/// Returns the single recipe that covers the most expiring inventory items,
/// along with the set of expiring names it would use. Returns null when:
/// - inventory has no expiring/expired items, OR
/// - no recipe matches any expiring item.
///
/// Distinct from [recommendedRecipesProvider]'s +0.5 ordering boost (Stage 2):
/// this provider gives a single, explicit answer to "which one dish best uses
/// my 临期 items today". UI: ExpiringFallbackCard on Dashboard.
final expiringFallbackRecipeProvider =
    Provider<({Recipe recipe, Set<String> coveredExpiringNames})?>((ref) {
      final inventory = ref.watch(inventoryProvider);
      final expiringNameSet = inventory
          .where(isNotFreshIngredient)
          .map((i) => i.name.trim().toLowerCase())
          .toSet();
      if (expiringNameSet.isEmpty) return null;

      final recipesAsync = ref.watch(recipesProvider);
      final customRecipes = ref.watch(customRecipesProvider);
      final base = recipesAsync.maybeWhen(
        data: (d) => d,
        orElse: () => const <Recipe>[],
      );
      final seen = base.map((r) => r.id).toSet();
      final all = [
        ...base,
        ...customRecipes.where((r) => !seen.contains(r.id)),
      ];

      ({Recipe recipe, Set<String> covered})? best;
      for (final recipe in all) {
        final covered = <String>{};
        for (final ri in recipe.ingredients) {
          final n = ri.name.trim().toLowerCase();
          if (expiringNameSet.contains(n)) covered.add(n);
        }
        if (covered.isEmpty) continue;
        if (best == null || covered.length > best.covered.length) {
          best = (recipe: recipe, covered: covered);
        }
      }
      if (best == null) return null;
      return (recipe: best.recipe, coveredExpiringNames: best.covered);
    });
