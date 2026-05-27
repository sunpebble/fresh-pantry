import 'dart:convert';

import '../models/recipe.dart';
import '../services/themealdb_service.dart';
import '../utils/normalize_cache_key.dart';
import 'storage_adapter.dart';

const recipeDetailsCacheStorageKey = 'recipe_details_cache';

String recipeSearchCacheKeyFor(String term) {
  return 'name:${normalizeCacheKey(term)}';
}

class RecipeSearchRepository {
  RecipeSearchRepository({required this.storage, required this.api});

  final StorageAdapter storage;
  final MealDbApi api;

  Future<List<Recipe>> searchByName(String term) async {
    final cache = _readCache();
    final key = recipeSearchCacheKeyFor(term);
    final cachedValue = cache[key];
    if (cachedValue is List) {
      return cachedValue
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList();
    }

    final recipes = await api.searchByName(term);
    cache[key] = recipes.map((recipe) => recipe.toJson()).toList();
    await storage.write(recipeDetailsCacheStorageKey, jsonEncode(cache));
    return recipes;
  }

  Map<String, dynamic> _readCache() {
    final raw = storage.read(recipeDetailsCacheStorageKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
}
