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
    for (var i = 0; i < inventory.length; i++) {
      final row = inventory[i];
      if (row.name.trim().toLowerCase() != candidateName) continue;
      if (row.unit.trim() != candidate.unit.trim()) continue;
      if (row.storage != candidate.storage) continue;
      return IntakeDefaultAction.mergeInto(i);
    }
    return const IntakeDefaultAction.newRow();
  }
}
