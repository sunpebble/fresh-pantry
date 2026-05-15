import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
}

void main() {
  test('seed + toggleSelected + toggleAction', () async {
    final c = await _container();
    final n = c.read(deductionReviewProvider.notifier);
    n.seed([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 1 把'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
      ),
    ]);
    expect(c.read(deductionReviewProvider).proposals, hasLength(1));

    n.toggleSelected('d1');
    expect(c.read(deductionReviewProvider).proposals.first.selected, isFalse);

    n.toggleAction('d1');
    expect(c.read(deductionReviewProvider).proposals.first.action,
        DeductionAction.skip);
    n.toggleAction('d1');
    expect(c.read(deductionReviewProvider).proposals.first.action,
        DeductionAction.deduct);
  });
}
