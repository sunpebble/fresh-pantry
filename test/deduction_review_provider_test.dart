import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  DeductionProposal proposal({
    String id = 'd1',
    bool selected = true,
    DeductionAction action = DeductionAction.deduct,
  }) => DeductionProposal(
    id: id,
    recipeIngredientName: '葱',
    requiredQty: '1把',
    candidates: const [
      DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 1 把'),
      DeductionCandidate(inventoryRowIndex: 1, displayLabel: '葱 2 把'),
    ],
    chosenIndex: 0,
    deductAmount: '1',
    selected: selected,
    action: action,
  );

  test('seed + toggleSelected + toggleAction', () async {
    final c = await _container();
    final n = c.read(deductionReviewProvider.notifier);
    n.seed([proposal()]);
    expect(c.read(deductionReviewProvider).proposals, hasLength(1));

    n.toggleSelected('d1');
    expect(c.read(deductionReviewProvider).proposals.first.selected, isFalse);

    n.toggleAction('d1');
    expect(
      c.read(deductionReviewProvider).proposals.first.action,
      DeductionAction.skip,
    );
    n.toggleAction('d1');
    expect(
      c.read(deductionReviewProvider).proposals.first.action,
      DeductionAction.deduct,
    );
  });

  test(
    'chooseCandidate and updateDeductAmount mutate only the target proposal',
    () async {
      final c = await _container();
      final n = c.read(deductionReviewProvider.notifier);
      n.seed([proposal(), proposal(id: 'd2')]);

      n.chooseCandidate('d1', 1);
      n.updateDeductAmount('d1', '0.5');

      final proposals = c.read(deductionReviewProvider).proposals;
      expect(proposals[0].chosenIndex, 1);
      expect(proposals[0].deductAmount, '0.5');
      expect(proposals[1].chosenIndex, 0);
      expect(proposals[1].deductAmount, '1');
    },
  );

  test('selectedCount counts only selected deduct actions', () async {
    final c = await _container();
    c.read(deductionReviewProvider.notifier).seed([
      proposal(id: 'deduct-selected'),
      proposal(id: 'deduct-unselected', selected: false),
      proposal(id: 'skip-selected', action: DeductionAction.skip),
    ]);

    expect(c.read(deductionReviewProvider).selectedCount, 1);

    c.read(deductionReviewProvider.notifier).clear();
    expect(c.read(deductionReviewProvider).selectedCount, 0);
  });

  test(
    'skip proposals stay unselected and cannot be toggled to deduct without candidates',
    () async {
      final c = await _container();
      final n = c.read(deductionReviewProvider.notifier);
      n.seed([
        DeductionProposal.empty(
          id: 'missing',
          recipeIngredientName: '罗勒',
          requiredQty: '1把',
        ),
      ]);

      n.toggleSelected('missing');
      n.toggleAction('missing');

      final p = c.read(deductionReviewProvider).proposals.single;
      expect(p.action, DeductionAction.skip);
      expect(p.selected, isFalse);
      expect(c.read(deductionReviewProvider).selectedCount, 0);
    },
  );

  test('toggleAction clears selection when a deduct row is skipped', () async {
    final c = await _container();
    final n = c.read(deductionReviewProvider.notifier);
    n.seed([proposal()]);

    n.toggleAction('d1');

    final p = c.read(deductionReviewProvider).proposals.single;
    expect(p.action, DeductionAction.skip);
    expect(p.selected, isFalse);
    expect(c.read(deductionReviewProvider).selectedCount, 0);
  });

  test('toggleSelectAll only targets deductible rows', () async {
    final c = await _container();
    final n = c.read(deductionReviewProvider.notifier);
    n.seed([
      proposal(id: 'd1'),
      proposal(id: 'd2'),
      DeductionProposal.empty(
        id: 'missing',
        recipeIngredientName: '罗勒',
        requiredQty: '1把',
      ),
    ]);

    n.toggleSelectAll();
    expect(c.read(deductionReviewProvider).selectedCount, 0);
    expect(c.read(deductionReviewProvider).proposals.last.selected, isFalse);

    n.toggleSelectAll();
    expect(c.read(deductionReviewProvider).selectedCount, 2);
    expect(c.read(deductionReviewProvider).proposals.last.selected, isFalse);
  });
}
