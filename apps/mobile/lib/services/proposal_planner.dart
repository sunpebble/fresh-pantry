import '../models/ingredient.dart';
import '../models/ingredient_identity.dart';
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
      // Bidirectional substring fuzzy match, but never let a length-1 inventory
      // name be a substring of a longer recipe ingredient (e.g. row "蛋" must
      // not match recipe "蛋糕"). The reverse direction (recipe term inside a
      // longer inventory name, e.g. "肉"→"猪肉末") stays intentionally loose.
      if (n == query || n.contains(query) || (query.contains(n) && n.length >= 2)) {
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
            inventoryRowId: m.$2.id,
            inventoryRowName: m.$2.name,
            inventoryRowUnit: m.$2.unit,
            displayLabel:
                '${m.$2.name} ${m.$2.quantity}${m.$2.unit}${m.$2.expiryLabel == null ? '' : ' · ${m.$2.expiryLabel}'}',
          ),
        )
        .toList();
  }

  /// Implements ADR-0001 merge rule γ via [IngredientIdentity]: perishables
  /// always new Batch; non-perishables merge when name×unit×storage match and
  /// the target row's quantity is numeric.
  static IntakeDefaultAction computeIntakeDefaultAction({
    required IntakeCandidate candidate,
    required List<Ingredient> inventory,
  }) {
    final index = IngredientIdentity.resolveMergeTarget(
      name: candidate.name,
      unit: candidate.unit,
      storage: candidate.storage,
      category: candidate.category,
      inventory: inventory,
    );
    return index < 0
        ? const IntakeDefaultAction.newRow()
        : IntakeDefaultAction.mergeInto(index);
  }
}
