import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/intake_review_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
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
  test('seed populates proposals and clears existing state', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '5',
        unit: '个',
        category: FoodCategories.other,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      ),
    ]);
    expect(c.read(intakeReviewProvider).proposals.length, 1);
  });

  test('toggleSelected flips selected flag', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '苹果', quantity: '5', unit: '个',
        category: null, storage: IconType.fridge, shelfLifeDays: 7,
      ),
    ]);
    n.toggleSelected('p1');
    expect(c.read(intakeReviewProvider).proposals.first.selected, isFalse);
  });

  test('toggleAction cycles newRow ↔ mergeInto when target is present', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '米', quantity: '3', unit: 'kg',
        category: FoodCategories.other, storage: IconType.pantry, shelfLifeDays: null,
        action: IntakeAction.newRow,
        mergeTargetId: '0',
        mergeTargetLabel: '米 5kg',
      ),
    ]);
    n.toggleAction('p1');
    expect(c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.mergeInto);
    n.toggleAction('p1');
    expect(c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.newRow);
  });

  test('applyToInventory wires through InventoryNotifier and clears state',
      () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([
      IntakeProposal(
        id: 'p1', name: '苹果', quantity: '5', unit: '个',
        category: null, storage: IconType.fridge, shelfLifeDays: 7,
      ),
    ]);
    await n.applyToInventory(c.read(inventoryProvider.notifier));
    expect(c.read(intakeReviewProvider).proposals, isEmpty);
    expect(c.read(inventoryProvider).length, 1);
  });
}
