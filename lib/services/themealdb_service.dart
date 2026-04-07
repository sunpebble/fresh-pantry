import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';

/// Service for fetching recipes from TheMealDB open API.
class TheMealDbService {
  static const _baseUrl = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 8);

  /// Search recipes by name. Returns up to 10 results.
  static Future<List<Recipe>> searchByName(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/search.php?s=${Uri.encodeComponent(query)}');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null) return [];

      return meals
          .take(10)
          .map((m) => _mealToRecipe(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Search recipes that use a specific ingredient.
  static Future<List<Recipe>> searchByIngredient(String ingredient) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/filter.php?i=${Uri.encodeComponent(ingredient)}',
      );
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null) return [];

      // filter.php returns minimal data; fetch full details for top 5
      final ids = meals
          .take(5)
          .map((m) => (m as Map<String, dynamic>)['idMeal'] as String)
          .toList();

      final recipes = <Recipe>[];
      for (final id in ids) {
        final recipe = await lookupById(id);
        if (recipe != null) recipes.add(recipe);
      }
      return recipes;
    } catch (_) {
      return [];
    }
  }

  /// Lookup a single recipe by TheMealDB ID.
  static Future<Recipe?> lookupById(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/lookup.php?i=$id');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null || meals.isEmpty) return null;

      return _mealToRecipe(meals.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetch a random recipe.
  static Future<Recipe?> random() async {
    try {
      final uri = Uri.parse('$_baseUrl/random.php');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null || meals.isEmpty) return null;

      return _mealToRecipe(meals.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Convert TheMealDB meal JSON to our Recipe model.
  static Recipe _mealToRecipe(Map<String, dynamic> meal) {
    final id = meal['idMeal'] as String? ?? '';
    final name = meal['strMeal'] as String? ?? '';
    final category = meal['strCategory'] as String? ?? '';
    final imageUrl = meal['strMealThumb'] as String?;
    final instructions = meal['strInstructions'] as String? ?? '';

    // Extract ingredients (TheMealDB uses strIngredient1..20 + strMeasure1..20)
    final ingredients = <RecipeIngredient>[];
    for (var i = 1; i <= 20; i++) {
      final ing = meal['strIngredient$i'] as String?;
      final measure = meal['strMeasure$i'] as String?;
      if (ing != null && ing.trim().isNotEmpty) {
        ingredients.add(RecipeIngredient(
          name: ing.trim(),
          amount: measure?.trim() ?? '',
        ));
      }
    }

    // Split instructions into steps by newline
    final steps = instructions
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Extract tags
    final tagsStr = meal['strTags'] as String?;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    // Estimate difficulty based on ingredient count
    final difficulty = ingredients.length <= 5
        ? 1
        : ingredients.length <= 10
            ? 2
            : 3;

    return Recipe(
      id: 'mealdb_$id',
      name: name,
      category: category,
      difficulty: difficulty,
      cookingMinutes: 30,
      description: steps.isNotEmpty ? steps.first : '',
      ingredients: ingredients,
      steps: steps,
      tags: tags,
      imageUrl: imageUrl,
    );
  }
}
