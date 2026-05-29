import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/_persistence_queue.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/sync/sync_enqueue.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';

const customRecipesStorageKey = CustomRecipeRepo.storageKey;

class CustomRecipeNotifier extends Notifier<List<Recipe>>
    with PersistenceQueue, SyncEnqueue<List<Recipe>> {
  late CustomRecipeRepo _repo;

  @override
  SyncEntityType get syncEntityType => SyncEntityType.customRecipe;

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

  Recipe _withSyncId(Recipe recipe) {
    final id = syncIdFor(recipe.id);
    return id == recipe.id ? recipe : recipe.copyWith(id: id);
  }

  Future<void> replaceFromRemote(List<Recipe> recipes) {
    return _mutate((_) => recipes);
  }

  Future<void> add(Recipe recipe) async {
    final recipeToAdd = _withSyncId(recipe);
    if (recipeToAdd.id.isEmpty || recipeToAdd.name.isEmpty) {
      return;
    }

    await _mutate((current) => [...current, recipeToAdd]);
    await enqueueSync(
      entityId: recipeToAdd.id,
      operation: SyncOperationType.create,
      patch: recipeToAdd.toJson(),
    );
  }

  Future<void> update(String id, Recipe recipe) async {
    if (id.isEmpty || recipe.name.isEmpty) {
      return;
    }

    final originalIndex = state.indexWhere((saved) => saved.id == id);
    if (originalIndex == -1) {
      return;
    }
    final original = state[originalIndex];
    final updatedRecipe = recipe.copyWith(id: id);
    await _mutate((current) {
      final index = current.indexWhere((saved) => saved.id == id);
      final next = [...current];
      next[index] = updatedRecipe;
      return next;
    });
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.update,
      patch: updatedRecipe.toJson(),
      baseVersion: original.remoteVersion,
    );
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) {
      return;
    }

    final originalIndex = state.indexWhere((recipe) => recipe.id == id);
    if (originalIndex == -1) {
      return;
    }
    final original = state[originalIndex];
    await _mutate((current) {
      final next = current.where((recipe) => recipe.id != id).toList();
      return next;
    });
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: original.remoteVersion,
    );
  }
}

final customRecipesProvider =
    NotifierProvider<CustomRecipeNotifier, List<Recipe>>(
      CustomRecipeNotifier.new,
    );
