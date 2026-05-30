import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/deduction_review_screen.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = newTestDatabase();
    addTearDown(db.close);
  });

  testWidgets('renders proposals and confirm button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
        child: const MaterialApp(home: DeductionReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeductionReviewScreen)),
    );
    container.read(deductionReviewProvider.notifier).seed([
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
    await tester.pumpAndSettle();

    expect(find.text('葱'), findsOneWidget);
    expect(find.textContaining('确认扣减 (1)'), findsOneWidget);
  });

  testWidgets('select all button toggles deductible rows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
        child: const MaterialApp(home: DeductionReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeductionReviewScreen)),
    );
    container.read(deductionReviewProvider.notifier).seed([
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
      DeductionProposal(
        id: 'd2',
        recipeIngredientName: '蒜',
        requiredQty: '1颗',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 1, displayLabel: '蒜 1 颗'),
        ],
        chosenIndex: 1,
        deductAmount: '1',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.textContaining('确认扣减 (2)'), findsOneWidget);

    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();

    expect(container.read(deductionReviewProvider).selectedCount, 0);
    expect(find.textContaining('确认扣减 (0)'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(container.read(deductionReviewProvider).selectedCount, 2);
    expect(find.textContaining('确认扣减 (2)'), findsOneWidget);
  });

  testWidgets('deduct amount stepper does not reduce below one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
        child: const MaterialApp(home: DeductionReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeductionReviewScreen)),
    );
    container.read(deductionReviewProvider.notifier).seed([
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pumpAndSettle();

    expect(
      container.read(deductionReviewProvider).proposals.single.deductAmount,
      '1',
    );
  });
}
