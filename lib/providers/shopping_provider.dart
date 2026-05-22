import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../storage/shopping_repo.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

String _shoppingItemNameKey(String name) => name.trim().toLowerCase();

ShoppingItem _normalizeShoppingItemCategory(ShoppingItem item) {
  final category =
      FoodCategories.normalize(item.category) ?? FoodCategories.other;
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

ShoppingItem _withUniqueShoppingItemId(
  ShoppingItem item,
  Set<String> existingIds,
) {
  final trimmedId = item.id.trim();
  final baseId = trimmedId.isEmpty ? ShoppingItem.newId() : trimmedId;
  var candidateId = baseId;
  var suffix = 2;

  while (existingIds.contains(candidateId)) {
    candidateId = '${baseId}_$suffix';
    suffix += 1;
  }

  existingIds.add(candidateId);
  return candidateId == item.id ? item : item.copyWith(id: candidateId);
}

class ShoppingNotifier extends Notifier<List<ShoppingItem>>
    with PersistenceQueue {
  late final ShoppingRepo _repo;

  @override
  List<ShoppingItem> build() {
    _repo = ref.read(shoppingRepoProvider);
    return _repo.loadAll();
  }

  Future<bool> add(ShoppingItem item) async {
    final normalizedItem = _withUniqueShoppingItemId(
      _normalizeShoppingItemCategory(item),
      state.map((item) => item.id).toSet(),
    );
    final nameKey = _shoppingItemNameKey(normalizedItem.name);
    if (nameKey.isEmpty ||
        state.any((item) => _shoppingItemNameKey(item.name) == nameKey)) {
      return false;
    }

    final updated = [...state, normalizedItem];
    state = updated;
    await queuePersistence(() async {
      _repo.saveItems(updated);
    });
    return true;
  }

  Future<void> remove(String id) async {
    final updated = state.where((item) => item.id != id).toList();
    if (updated.length == state.length) {
      return;
    }

    state = updated;
    await queuePersistence(() async {
      _repo.saveItems(updated);
    });
  }

  Future<void> toggleCheck(String id) async {
    var changed = false;
    final updated =
        state.map((item) {
          if (item.id == id) {
            changed = true;
            return item.copyWith(isChecked: !item.isChecked);
          }
          return item;
        }).toList();
    if (!changed) {
      return;
    }

    state = updated;
    await queuePersistence(() async {
      _repo.saveItems(updated);
    });
  }

  Future<bool> addFromIngredient(Ingredient ingredient) {
    return add(ShoppingItem.fromIngredient(ingredient));
  }

  Future<bool> addFromSuggestion(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;

    final newItem = ShoppingItem(
      id: ShoppingItem.newId(),
      name: trimmedName,
      detail: '',
      category: FoodKnowledge.categoryFor(trimmedName),
    );
    return add(newItem);
  }
}

final shoppingProvider = NotifierProvider<ShoppingNotifier, List<ShoppingItem>>(
  ShoppingNotifier.new,
);

final groupedShoppingProvider = Provider<Map<String, List<ShoppingItem>>>((
  ref,
) {
  final items = ref.watch(shoppingProvider);
  final grouped = <String, List<ShoppingItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.category, () => []).add(item);
  }
  return grouped;
});

final checkedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => item.isChecked).length;
});

final uncheckedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => !item.isChecked).length;
});
