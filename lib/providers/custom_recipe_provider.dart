import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/utils/json_object_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

const customRecipesStorageKey = 'custom_recipes';

class CustomRecipeNotifier extends Notifier<List<Recipe>> {
  late SharedPreferences _prefs;
  Future<void> _pendingPersistence = Future.value();

  @override
  List<Recipe> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<Recipe> _load() {
    final saved = _prefs.getString(customRecipesStorageKey);
    if (saved == null) {
      return const [];
    }

    try {
      return decodeJsonObjectList(saved)
          .map(Recipe.fromJson)
          .where((recipe) => recipe.id.isNotEmpty && recipe.name.isNotEmpty)
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> _save(List<Recipe> recipes) async {
    final saved = await _prefs.setString(
      customRecipesStorageKey,
      json.encode(recipes.map((recipe) => recipe.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Failed to save custom recipes');
    }
  }

  Future<void> _mutate(List<Recipe> Function(List<Recipe>) nextState) {
    final mutation = _pendingPersistence.then((_) async {
      final current = state;
      final next = nextState(current);
      if (identical(next, current)) {
        return;
      }

      await _save(next);
      state = next;
    });
    _pendingPersistence = mutation.catchError((_) {});
    return mutation;
  }

  Future<void> add(Recipe recipe) async {
    if (recipe.id.isEmpty || recipe.name.isEmpty) {
      return;
    }

    await _mutate((current) => [...current, recipe]);
  }

  Future<void> update(String id, Recipe recipe) async {
    if (id.isEmpty || recipe.name.isEmpty) {
      return;
    }

    await _mutate((current) {
      final index = current.indexWhere((saved) => saved.id == id);
      if (index == -1) {
        return current;
      }

      final next = [...current];
      next[index] = recipe.copyWith(id: id);
      return next;
    });
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) {
      return;
    }

    await _mutate((current) {
      final next = current.where((recipe) => recipe.id != id).toList();
      if (next.length == current.length) {
        return current;
      }

      return next;
    });
  }
}

final customRecipesProvider =
    NotifierProvider<CustomRecipeNotifier, List<Recipe>>(
      CustomRecipeNotifier.new,
    );
