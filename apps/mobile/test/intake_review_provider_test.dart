import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/intake_review_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/test_database.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...testStorageOverrides(database: db),
    ],
  );
}

void main() {
  IntakeProposal proposal({
    String id = 'p1',
    String name = '苹果',
    String quantity = '5',
    String unit = '个',
    String? category = FoodCategories.other,
    IconType storage = IconType.fridge,
    int? shelfLifeDays = 7,
    IntakeAction action = IntakeAction.newRow,
    String? mergeTargetId,
    String? mergeTargetLabel,
    bool selected = true,
  }) => IntakeProposal(
    id: id,
    name: name,
    quantity: quantity,
    unit: unit,
    category: category,
    storage: storage,
    shelfLifeDays: shelfLifeDays,
    action: action,
    mergeTargetId: mergeTargetId,
    mergeTargetLabel: mergeTargetLabel,
    selected: selected,
  );

  test('seed populates proposals and clears existing state', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([proposal()]);
    expect(c.read(intakeReviewProvider).proposals.length, 1);
  });

  test('toggleSelected flips selected flag', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([proposal(category: null)]);
    n.toggleSelected('p1');
    expect(c.read(intakeReviewProvider).proposals.first.selected, isFalse);
  });

  test(
    'toggleAction cycles newRow ↔ mergeInto when target is present',
    () async {
      final c = await _container();
      final n = c.read(intakeReviewProvider.notifier);
      n.seed([
        proposal(
          name: '米',
          quantity: '3',
          unit: 'kg',
          storage: IconType.pantry,
          shelfLifeDays: null,
          mergeTargetId: '0',
          mergeTargetLabel: '米 5kg',
        ),
      ]);
      n.toggleAction('p1');
      expect(
        c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.mergeInto,
      );
      n.toggleAction('p1');
      expect(
        c.read(intakeReviewProvider).proposals.first.action,
        IntakeAction.newRow,
      );
    },
  );

  test(
    'updateProposal, toggleSelectAll, and selectedCount track applied rows',
    () async {
      final c = await _container();
      final n = c.read(intakeReviewProvider.notifier);
      n.seed([
        proposal(id: 'p1'),
        proposal(
          id: 'p2',
          selected: false,
          shelfLifeDays: null,
          quantity: '9999',
        ),
      ]);

      n.updateProposal(proposal(id: 'p2', name: '梨', quantity: '2'));
      expect(c.read(intakeReviewProvider).proposals[1].name, '梨');
      expect(c.read(intakeReviewProvider).selectedCount, 2);

      n.toggleSelectAll();
      expect(c.read(intakeReviewProvider).selectedCount, 0);
      n.toggleSelectAll();
      expect(c.read(intakeReviewProvider).selectedCount, 2);
    },
  );

  test('build recovers from corrupted persisted draft JSON', () async {
    SharedPreferences.setMockInitialValues({intakeReviewDraftKey: 'not-json'});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(intakeReviewProvider).proposals, isEmpty);
  });

  test('records persistence error when saving draft fails', () async {
    final c = await _container();
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    SharedPreferencesStorePlatform.instance = _ThrowingPreferencesStore();

    final n = c.read(intakeReviewProvider.notifier);
    n.seed([proposal()]);
    await Future<void>.delayed(Duration.zero);

    final state = c.read(intakeReviewProvider);
    expect(state.proposals, hasLength(1));
    expect(state.persistError, isA<StateError>());
  });

  test('records persistence error when clearing draft fails', () async {
    final c = await _container();
    final n = c.read(intakeReviewProvider.notifier);
    n.seed([proposal()]);
    await Future<void>.delayed(Duration.zero);

    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    SharedPreferencesStorePlatform.instance = _ThrowingPreferencesStore();
    n.clear();
    await Future<void>.delayed(Duration.zero);

    final state = c.read(intakeReviewProvider);
    expect(state.proposals, isEmpty);
    expect(state.persistError, isA<StateError>());
  });

  test(
    'applyToInventory wires through InventoryNotifier and clears state',
    () async {
      final c = await _container();
      final n = c.read(intakeReviewProvider.notifier);
      n.seed([proposal(category: null)]);
      await n.applyToInventory(c.read(inventoryProvider.notifier));
      expect(c.read(intakeReviewProvider).proposals, isEmpty);
      expect(c.read(inventoryProvider).length, 1);
    },
  );
}

class _ThrowingPreferencesStore extends InMemorySharedPreferencesStore {
  _ThrowingPreferencesStore() : super.empty();

  @override
  Future<bool> remove(String key) async {
    throw StateError('remove failed');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw StateError('write failed');
  }
}
