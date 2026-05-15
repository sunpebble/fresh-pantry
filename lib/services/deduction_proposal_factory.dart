import '../models/ingredient.dart';
import '../models/proposal.dart';
import '../models/recipe.dart';
import 'proposal_planner.dart';

class DeductionProposalFactory {
  DeductionProposalFactory._();

  static List<DeductionProposal> forRecipe(
    Recipe recipe,
    List<Ingredient> inventory,
  ) {
    final list = <DeductionProposal>[];
    for (var i = 0; i < recipe.ingredients.length; i++) {
      final ri = recipe.ingredients[i];
      final candidates =
          ProposalPlanner.fuzzyMatchInventoryRows(ri.name, inventory);
      if (candidates.isEmpty) {
        list.add(DeductionProposal.empty(
          id: 'd_${recipe.id}_$i',
          recipeIngredientName: ri.name,
          requiredQty: ri.amount,
        ));
      } else {
        list.add(DeductionProposal(
          id: 'd_${recipe.id}_$i',
          recipeIngredientName: ri.name,
          requiredQty: ri.amount,
          candidates: candidates,
          chosenIndex: candidates.first.inventoryRowIndex,
          deductAmount: ri.quantity.trim().isEmpty ? '1' : ri.quantity,
        ));
      }
    }
    return list;
  }
}
