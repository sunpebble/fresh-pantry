// lib/services/intake_proposal_factory.dart
import '../models/ingredient.dart';
import '../models/ingredient_draft.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'proposal_planner.dart';

class IntakeProposalFactory {
  IntakeProposalFactory._();

  static List<IntakeProposal> fromDrafts(
    List<IngredientDraft> drafts,
    List<Ingredient> inventory,
  ) {
    return drafts.map((d) {
      final candidate = _Candidate(d);
      final defaultAction = ProposalPlanner.computeIntakeDefaultAction(
        candidate: candidate,
        inventory: inventory,
      );
      final i = defaultAction.targetIndex;
      return IntakeProposal(
        id: d.id,
        name: d.name.value,
        quantity: d.quantity.value,
        unit: d.unit.value,
        category: d.category.value,
        storage: d.storage.value ?? IconType.fridge,
        shelfLifeDays: d.shelfLifeDays.value,
        action: defaultAction.kind,
        mergeTargetId: i?.toString(),
        mergeTargetLabel: i == null
            ? null
            : '${inventory[i].name} ${inventory[i].quantity}${inventory[i].unit}',
      );
    }).toList();
  }
}

class _Candidate implements IntakeCandidate {
  _Candidate(this.d);
  final IngredientDraft d;
  @override
  String get name => d.name.value;
  @override
  String get unit => d.unit.value;
  @override
  IconType get storage => d.storage.value ?? IconType.fridge;
  @override
  String? get category => d.category.value;
}
