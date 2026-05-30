import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../models/recipe.dart';

class CustomRecipeRepo {
  CustomRecipeRepo(this._db);

  final AppDatabase _db;

  final Map<String, List<Recipe>> _seed = {};

  void hydrate(String householdId, List<Recipe> recipes) {
    _seed[householdId] = List<Recipe>.unmodifiable(recipes);
  }

  List<Recipe> loadAll(String householdId) =>
      _seed[householdId] ?? const <Recipe>[];

  Future<List<Recipe>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.customRecipes)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final result = <Recipe>[];
    for (final row in rows) {
      try {
        if (row.id.isEmpty) continue;
        final recipe = _decode(row);
        if (recipe.id.isEmpty || recipe.name.isEmpty) continue;
        result.add(recipe);
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  Future<void> saveRecipes(String householdId, List<Recipe> recipes) async {
    await _db.transaction(() async {
      await (_db.delete(_db.customRecipes)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      for (final recipe in recipes) {
        await _db.into(_db.customRecipes).insertOnConflictUpdate(
              _encode(householdId, recipe),
            );
      }
    });
  }

  CustomRecipesCompanion _encode(String householdId, Recipe recipe) {
    return CustomRecipesCompanion.insert(
      id: recipe.id,
      householdId: householdId,
      payload: jsonEncode(recipe.toJson()),
    );
  }

  Recipe _decode(CustomRecipe row) {
    return Recipe.fromJson(jsonDecode(row.payload) as Map<String, dynamic>);
  }
}
