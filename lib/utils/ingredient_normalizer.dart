import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/ingredient.dart';
import 'expiry_calculator.dart';

Ingredient normalizeIngredientCategory(Ingredient item) {
  final category = FoodCategories.normalize(item.category);
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

int? shelfLifeDaysFor(Ingredient item) {
  final expiryDate = item.expiryDate;
  if (expiryDate == null) return null;

  final savedShelfLifeDays = item.shelfLifeDays;
  if (savedShelfLifeDays != null && savedShelfLifeDays > 0) {
    return savedShelfLifeDays;
  }

  final defaultShelfLifeDays = FoodKnowledge.lookup(item.name)?.shelfLifeDays;
  if (defaultShelfLifeDays != null && defaultShelfLifeDays > 0) {
    return defaultShelfLifeDays;
  }

  if (item.addedAt == null) return null;

  final days = calendarDaysBetween(item.addedAt!, expiryDate);
  return days > 0 ? days : null;
}

Ingredient refreshIngredientFreshness(Ingredient item, {DateTime? now}) {
  final expiryDate = item.expiryDate;
  if (expiryDate == null) return item;

  final shelfLife = shelfLifeDaysFor(item);
  if (shelfLife == null) {
    return item.copyWith(expiryLabel: expiryLabelFor(expiryDate, now: now));
  }

  final freshness = expiryFreshness(
    expiryDate: expiryDate,
    totalShelfLifeDays: shelfLife,
    now: now,
  );

  return item.copyWith(
    freshnessPercent: freshness,
    state: freshnessStateForExpiry(
      freshness: freshness,
      expiryDate: expiryDate,
      now: now,
    ),
    expiryLabel: expiryLabelFor(expiryDate, now: now),
  );
}

Ingredient normalizeInventoryIngredient(Ingredient item) {
  return refreshIngredientFreshness(normalizeIngredientCategory(item));
}
