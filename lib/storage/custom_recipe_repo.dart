import 'dart:convert';
import '../models/recipe.dart';
import '../utils/json_object_list.dart';
import 'storage_adapter.dart';

class CustomRecipeRepo {
  static const storageKey = 'custom_recipes';

  final StorageAdapter _adapter;
  List<Recipe>? _hydratedSeed;

  CustomRecipeRepo(this._adapter);

  void hydrate(List<Recipe> seed) {
    _hydratedSeed = seed;
  }

  List<Recipe> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final saved = _adapter.read(storageKey);
    if (saved == null) return [];
    try {
      return decodeJsonObjectList(saved)
          .map(Recipe.fromJson)
          .where((recipe) => recipe.id.isNotEmpty && recipe.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void saveRecipes(List<Recipe> recipes) {
    _adapter.write(
      storageKey,
      json.encode(recipes.map((recipe) => recipe.toJson()).toList()),
    );
  }
}
