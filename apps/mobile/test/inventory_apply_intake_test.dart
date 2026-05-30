import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

Future<ProviderContainer> _container({
  List<Ingredient> seed = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    ...testStorageOverrides(database: newTestDatabase()),
    sharedPreferencesProvider.overrideWithValue(prefs),
    inventorySeedProvider.overrideWithValue(seed),
  ]);
}

IntakeProposal _newRow({
  String id = 'p1',
  String name = '苹果',
  String quantity = '5',
  String unit = '个',
  String category = FoodCategories.other,
  IconType storage = IconType.fridge,
  int? shelfLifeDays = 7,
}) =>
    IntakeProposal(
      id: id,
      name: name,
      quantity: quantity,
      unit: unit,
      category: category,
      storage: storage,
      shelfLifeDays: shelfLifeDays,
      action: IntakeAction.newRow,
    );

void main() {
  test('applyIntakeProposals: newRow creates an Ingredient', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyIntakeProposals([_newRow()]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1);
    expect(state.first.name, '苹果');
    expect(state.first.quantity, '5');
  });

  test('applyIntakeProposals: mergeInto adds quantity to existing row',
      () async {
    final existing = Ingredient(
      name: '米',
      quantity: '3',
      unit: 'kg',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      category: FoodCategories.other,
      storage: IconType.pantry,
    );
    final c = await _container(seed: [existing]);
    final notifier = c.read(inventoryProvider.notifier);

    final merge = IntakeProposal(
      id: 'p2',
      name: '米',
      quantity: '5',
      unit: 'kg',
      category: FoodCategories.other,
      storage: IconType.pantry,
      shelfLifeDays: null,
      action: IntakeAction.mergeInto,
      mergeTargetId: '0', // index 0 as string
    );

    await notifier.applyIntakeProposals([merge]);

    final state = c.read(inventoryProvider);
    expect(state.length, 1,
        reason: 'merge must not create a new row');
    expect(state.first.quantity, '8',
        reason: 'quantity must sum 3 + 5 = 8');
  });

  test('applyIntakeProposals: skipped (selected=false) is ignored', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    final unselected = _newRow(id: 'p3').copyWith(selected: false);

    await notifier.applyIntakeProposals([unselected]);

    expect(c.read(inventoryProvider), isEmpty);
  });

  test('applyIntakeProposals: mixed list applies in given order', () async {
    final c = await _container();
    final notifier = c.read(inventoryProvider.notifier);

    await notifier.applyIntakeProposals([
      _newRow(id: 'a', name: '苹果'),
      _newRow(id: 'b', name: '香蕉'),
    ]);

    final state = c.read(inventoryProvider);
    expect(state.map((e) => e.name).toList(), ['苹果', '香蕉']);
  });
}
