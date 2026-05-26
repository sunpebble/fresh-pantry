import '../data/food_knowledge.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../models/storage_area.dart';

abstract final class IngredientFactory {
  static Ingredient fromShoppingItem(ShoppingItem item, {DateTime? now}) {
    final defaults = FoodKnowledge.lookup(item.name);
    final addedAt = now ?? DateTime.now();
    final shelfLifeDays = defaults?.shelfLifeDays;
    final expiryDate =
        shelfLifeDays == null
            ? null
            : addedAt.add(Duration(days: shelfLifeDays));

    return Ingredient(
      name: item.name,
      quantity: '1',
      unit: '份',
      imageUrl: item.imageUrl ?? '',
      freshnessPercent: expiryDate == null ? 0.85 : 1.0,
      state: FreshnessState.fresh,
      category: FoodKnowledge.categoryFor(item.name),
      storage: defaults?.storage ?? IconType.fridge,
      expiryDate: expiryDate,
      addedAt: addedAt,
      shelfLifeDays: shelfLifeDays,
      expiryLabel: expiryDate == null ? '新鲜' : '$shelfLifeDays天后过期',
    );
  }
}
