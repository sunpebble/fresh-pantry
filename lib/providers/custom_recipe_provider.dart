import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/_persistence_queue.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';

const customRecipesStorageKey = CustomRecipeRepo.storageKey;

class CustomRecipeNotifier extends Notifier<List<Recipe>>
    with PersistenceQueue {
  late CustomRecipeRepo _repo;

  @override
  List<Recipe> build() {
    _repo = ref.read(customRecipeRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _mutate(List<Recipe> Function(List<Recipe>) nextState) {
    return queuePersistence(() async {
      final current = state;
      final next = nextState(current);
      if (identical(next, current)) {
        return;
      }

      _repo.saveRecipes(next);
      state = next;
    });
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
