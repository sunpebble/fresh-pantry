import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/recipe.dart';

const String howtocookAssetKey = 'assets/recipes/howtocook.json';

/// 从打包的 asset 读取 HowToCook 本地中文食谱，解析结果按实例缓存。
class LocalRecipeRepository {
  LocalRecipeRepository({Future<String> Function(String key)? loadString})
    : _loadString = loadString ?? rootBundle.loadString;

  final Future<String> Function(String key) _loadString;
  List<Recipe>? _cache;

  Future<List<Recipe>> loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await _loadString(howtocookAssetKey);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('howtocook.json must be a JSON array');
    }
    final recipes = <Recipe>[];
    for (final entry in decoded.whereType<Map<String, dynamic>>()) {
      try {
        recipes.add(Recipe.fromJson(entry));
      } catch (e) {
        if (kDebugMode) debugPrint('Skipping malformed recipe: $e');
      }
    }
    _cache = recipes;
    return recipes;
  }
}
