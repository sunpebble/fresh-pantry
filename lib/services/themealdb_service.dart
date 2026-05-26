import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import '../utils/json_cast.dart';
import '_http.dart';

abstract class MealDbApi {
  Future<List<Recipe>> searchByName(String term);
}

/// Service for fetching recipes from TheMealDB open API.
class TheMealDbService implements MealDbApi {
  const TheMealDbService({this.client});

  final http.Client? client;

  static const _baseUrl = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 8);
  static const _retryCount = 1;
  static const _retryDelay = Duration(milliseconds: 500);
  static const _maxSearchResults = 10;
  static const _maxIngredients = 20;
  static const _easyIngredientThreshold = 5;
  static const _mediumIngredientThreshold = 10;
  static const _defaultCookingMinutes = 30;
  static const _headers = <String, String>{
    'User-Agent': 'FreshPantry/1.0 (Flutter)',
  };

  @override
  Future<List<Recipe>> searchByName(String query) {
    return _searchByName(query, client: client);
  }

  /// Search recipes by name. Returns up to [_maxSearchResults] results.
  static Future<List<Recipe>> _searchByName(
    String query, {
    http.Client? client,
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/search.php?s=${Uri.encodeComponent(query)}',
      );
      final response = await _fetch(uri, client: client);

      if (response.statusCode != 200) return [];

      final json = asJsonMap(jsonDecode(response.body));
      if (json == null) return [];

      final meals = asJsonList(json['meals']);
      if (meals == null) return [];

      return meals
          .take(_maxSearchResults)
          .whereType<Map<String, dynamic>>()
          .map(_mealToRecipe)
          .toList();
    } on TimeoutException catch (e, stack) {
      debugPrint('TheMealDB searchByName timeout: $e\n$stack');
      return [];
    } on http.ClientException catch (e, stack) {
      debugPrint('TheMealDB searchByName HTTP error: $e\n$stack');
      return [];
    } on FormatException catch (e, stack) {
      debugPrint('TheMealDB searchByName format error: $e\n$stack');
      return [];
    } catch (e, stack) {
      debugPrint('TheMealDB searchByName unexpected error: $e\n$stack');
      return [];
    }
  }

  /// Convert TheMealDB meal JSON to our Recipe model.
  static Recipe _mealToRecipe(Map<String, dynamic> meal) {
    final id = meal['idMeal']?.toString() ?? '';
    final name = asJsonString(meal['strMeal']) ?? '';
    final category = asJsonString(meal['strCategory']) ?? '';
    final imageUrl = asJsonString(meal['strMealThumb']);
    final instructions = asJsonString(meal['strInstructions']) ?? '';

    // Extract ingredients (TheMealDB uses strIngredient1..20 + strMeasure1..20)
    final ingredients = <RecipeIngredient>[];
    for (var i = 1; i <= _maxIngredients; i++) {
      final ing = asJsonString(meal['strIngredient$i']);
      final measure = asJsonString(meal['strMeasure$i']);
      if (ing != null && ing.trim().isNotEmpty) {
        ingredients.add(
          RecipeIngredient(name: ing.trim(), amount: measure?.trim() ?? ''),
        );
      }
    }

    // Split instructions into steps by newline
    final steps =
        instructions
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    // Extract tags
    final tagsStr = asJsonString(meal['strTags']);
    final tags =
        tagsStr != null
            ? tagsStr
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList()
            : <String>[];

    // Estimate difficulty based on ingredient count
    final difficulty =
        ingredients.length <= _easyIngredientThreshold
            ? 1
            : ingredients.length <= _mediumIngredientThreshold
            ? 2
            : 3;

    return Recipe(
      id: 'mealdb_$id',
      name: name,
      category: category,
      difficulty: difficulty,
      cookingMinutes: _defaultCookingMinutes,
      description: steps.isNotEmpty ? steps.first : '',
      ingredients: ingredients,
      steps: steps,
      tags: tags,
      imageUrl: imageUrl,
    );
  }

  /// Perform an HTTP GET with retry logic.
  static Future<http.Response> _fetch(Uri uri, {http.Client? client}) {
    return fetchWithRetry(
      uri,
      client: client,
      timeout: _timeout,
      retryDelay: _retryDelay,
      retryCount: _retryCount,
      headers: _headers,
    );
  }
}
