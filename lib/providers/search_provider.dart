import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'inventory_provider.dart';
import 'shopping_provider.dart';
import 'food_details_provider.dart';
import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';

/// Current search keyword
final searchProvider = StateProvider<String>((ref) => '');

/// Filtered inventory based on search keyword
final filteredInventoryProvider = Provider<List<Ingredient>>((ref) {
  final keyword = ref.watch(searchProvider).trim().toLowerCase();
  final items = ref.watch(inventoryProvider);

  if (keyword.isEmpty) return items;

  return items.where((item) {
    return item.name.toLowerCase().contains(keyword) ||
        (item.category?.toLowerCase().contains(keyword) ?? false);
  }).toList();
});

/// Filtered shopping list based on search keyword
final filteredShoppingProvider = Provider<List<ShoppingItem>>((ref) {
  final keyword = ref.watch(searchProvider).trim().toLowerCase();
  final items = ref.watch(shoppingProvider);

  if (keyword.isEmpty) return items;

  return items.where((item) {
    return item.name.toLowerCase().contains(keyword) ||
        item.category.toLowerCase().contains(keyword);
  }).toList();
});

/// Online food details for the current search keyword.
///
/// `autoDispose` keeps the cache lean once the search overlay is closed.
/// A 300ms debounce window swallows rapid keystrokes — if the keyword changes
/// while we're waiting, the provider re-runs and `ref.mounted` short-circuits
/// the stale invocation before any network work happens.
final searchFoodDetailsProvider = FutureProvider.autoDispose<FoodDetails?>((
  ref,
) async {
  final keyword = ref.watch(searchProvider).trim();
  if (keyword.length < 2) return null;

  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ref.mounted) return null;

  final defaults = FoodKnowledge.lookup(keyword);
  final ingredient = Ingredient(
    name: keyword,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category:
        defaults?.category ??
        FoodKnowledge.categoryFor(keyword, fallback: FoodCategories.other),
    storage: defaults?.storage ?? IconType.fridge,
    shelfLifeDays: defaults?.shelfLifeDays,
  );

  return ref.watch(foodDetailsRepositoryProvider).detailsFor(ingredient);
});

/// Search history — stores recent search terms (max 10)
class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void add(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    // Remove if already exists, then add to front
    state = [trimmed, ...state.where((t) => t != trimmed)].take(10).toList();
  }

  void remove(String term) {
    state = state.where((t) => t != term).toList();
  }

  void clear() {
    state = [];
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );
