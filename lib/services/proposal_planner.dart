import '../data/food_categories.dart';
import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';

/// Minimal duck-typed view of an intake's identity fields. Both
/// `IngredientDraft` (paste flow) and `ShoppingItem` (shopping flow) can
/// implement this on the fly when calling [ProposalPlanner].
abstract class IntakeCandidate {
  String get name;
  String get unit;
  IconType get storage;
  String? get category;
}

class IntakeDefaultAction {
  const IntakeDefaultAction.newRow()
    : kind = IntakeAction.newRow,
      targetIndex = null;
  const IntakeDefaultAction.mergeInto(int index)
    : kind = IntakeAction.mergeInto,
      targetIndex = index;
  final IntakeAction kind;
  final int? targetIndex;
}

class ProposalPlanner {
  ProposalPlanner._();

  static List<DeductionCandidate> fuzzyMatchInventoryRows(
    String recipeIngredientName,
    List<Ingredient> inventory,
  ) {
    final query = recipeIngredientName.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final matches = <(int, Ingredient)>[];
    for (var i = 0; i < inventory.length; i++) {
      final n = inventory[i].name.trim().toLowerCase();
      if (n.isEmpty) continue;
      if (n == query || n.contains(query) || query.contains(n)) {
        matches.add((i, inventory[i]));
      }
    }
    matches.sort((a, b) {
      final ea = a.$2.expiryDate;
      final eb = b.$2.expiryDate;
      if (ea == null && eb == null) return 0;
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });
    return matches
        .map(
          (m) => DeductionCandidate(
            inventoryRowIndex: m.$1,
            displayLabel:
                '${m.$2.name} ${m.$2.quantity}${m.$2.unit}${m.$2.expiryLabel == null ? '' : ' · ${m.$2.expiryLabel}'}',
          ),
        )
        .toList();
  }

  /// Implements ADR-0001 merge rule γ: perishables always new Batch;
  /// non-perishables merge when name+unit+storage match.
  static IntakeDefaultAction computeIntakeDefaultAction({
    required IntakeCandidate candidate,
    required List<Ingredient> inventory,
  }) {
    if (FoodCategories.isPerishable(candidate.category)) {
      return const IntakeDefaultAction.newRow();
    }
    final candidateName = candidate.name.trim().toLowerCase();
    final candidateUnit = candidate.unit.trim();
    if (candidateName.isEmpty || candidateUnit.isEmpty) {
      return const IntakeDefaultAction.newRow();
    }
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      if (row.name.trim().isEmpty) continue;
      if (row.name.trim().toLowerCase() != candidateName) continue;
      if (row.unit.trim() != candidateUnit) continue;
      if (row.storage != candidate.storage) continue;
      return IntakeDefaultAction.mergeInto(i);
    }
    return const IntakeDefaultAction.newRow();
  }
}
