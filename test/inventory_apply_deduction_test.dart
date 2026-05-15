import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Ingredient _ing(String name, String qty, {String unit = '个'}) => Ingredient(
      name: name,
      quantity: qty,
      unit: unit,
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.fridge,
    );

Future<ProviderContainer> _container(List<Ingredient> seed) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(seed),
  ]);
}

void main() {
  test('deducts qty from chosen row', () async {
    final c = await _container([_ing('葱', '3')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 3 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1);
    expect(state.first.quantity, '2');
  });

  test('removes row when qty reaches 0', () async {
    final c = await _container([_ing('蒜', '1')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '蒜',
        requiredQty: '1瓣',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '蒜 1 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider), isEmpty);
  });

  test('skip action does not mutate inventory', () async {
    final c = await _container([_ing('葱', '3')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal.empty(
        id: 'd1',
        recipeIngredientName: '葱',
        requiredQty: '1把',
      ),
    ]);

    expect(c.read(inventoryProvider).first.quantity, '3');
  });

  test('clamps negative result to 0 (and removes row)', () async {
    final c = await _container([_ing('盐', '0.5')]);
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyDeductionProposals([
      DeductionProposal(
        id: 'd1',
        recipeIngredientName: '盐',
        requiredQty: '1勺',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '盐 0.5'),
        ],
        chosenIndex: 0,
        deductAmount: '2',
        action: DeductionAction.deduct,
      ),
    ]);

    expect(c.read(inventoryProvider), isEmpty);
  });
}
