import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import 'ingredient.dart';
import 'storage_area.dart';

/// Owns the ADR-0001 Ingredient identity rule: identity is
/// `name × unit × Storage Area × (Batch for Perishables)`.
///
/// This is the single place that decides whether an Intake merges into an
/// existing row or starts a new Batch. Both the proposal-time default
/// (`ProposalPlanner`) and the apply-time re-resolution (`InventoryNotifier`)
/// call through here, so the displayed default can never drift from what apply
/// actually does.
class IngredientIdentity {
  IngredientIdentity._();

  /// A Perishable always creates a new Batch (ADR-0001). The knowledge base is
  /// consulted by name too, so a perishable purchase whose category is missing
  /// or defaulted to "其他" is not silently merged into an aging row.
  static bool isPerishable({String? category, required String name}) {
    return FoodCategories.isPerishable(category) ||
        FoodKnowledge.isPerishableName(name);
  }

  /// Resolves the index of the inventory row an Intake should merge into, or
  /// `-1` meaning "create a new row instead".
  ///
  /// Returns `-1` when the item is Perishable (every intake is a new Batch),
  /// when name/unit are blank, when no row matches name×unit×storage, or when
  /// the matching row's quantity is non-numeric (merging would silently discard
  /// its stock).
  static int resolveMergeTarget({
    required String name,
    required String unit,
    required IconType storage,
    String? category,
    required List<Ingredient> inventory,
  }) {
    if (isPerishable(category: category, name: name)) return -1;
    final normalizedName = name.trim().toLowerCase();
    final normalizedUnit = unit.trim();
    if (normalizedName.isEmpty || normalizedUnit.isEmpty) return -1;
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      if (row.name.trim().isEmpty) continue;
      if (row.name.trim().toLowerCase() != normalizedName) continue;
      if (row.unit.trim() != normalizedUnit) continue;
      if (row.storage != storage) continue;
      if (double.tryParse(row.quantity.trim()) == null) return -1;
      return i;
    }
    return -1;
  }
}
