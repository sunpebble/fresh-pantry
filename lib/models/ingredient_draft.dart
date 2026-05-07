import '../providers/inventory_provider.dart' show expiryLabelFor;
import '../utils/expiry_calculator.dart';
import 'draft_field.dart';
import 'ingredient.dart';
import 'storage_area.dart';

class IngredientDraft {
  IngredientDraft({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    this.selected = true,
  });

  final String id;
  DraftField<String> name;
  DraftField<String> quantity;
  DraftField<String> unit;
  DraftField<String?> category;
  DraftField<IconType?> storage;
  DraftField<int?> shelfLifeDays;
  bool selected;

  Ingredient toIngredient() {
    final days = shelfLifeDays.value;
    final today = DateTime.now();
    final expiry = days == null ? null : today.add(Duration(days: days));
    final freshness = expiry == null
        ? 0.85
        : expiryFreshness(expiryDate: expiry, totalShelfLifeDays: days ?? 7);
    return Ingredient(
      name: name.value,
      quantity: quantity.value,
      unit: unit.value,
      imageUrl: '',
      freshnessPercent: freshness,
      state: freshnessStateForExpiry(freshness: freshness, expiryDate: expiry),
      category: category.value,
      storage: storage.value ?? IconType.fridge,
      expiryDate: expiry,
      expiryLabel: expiry == null ? '新鲜' : expiryLabelFor(expiry),
      shelfLifeDays: days,
    );
  }
}
