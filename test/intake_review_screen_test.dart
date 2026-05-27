import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/intake_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/intake_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders one proposal row and shows confirm count', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: IntakeReviewScreen()),
      ),
    );
    // Empty state visible
    expect(find.textContaining('没有待审核'), findsOneWidget);

    // Seed and rebuild
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntakeReviewScreen)),
    );
    container.read(intakeReviewProvider.notifier).seed([
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
    await tester.pumpAndSettle();
    expect(find.text('苹果'), findsOneWidget);
    expect(find.textContaining('入库 (1)'), findsOneWidget);
  });

  testWidgets('quantity stepper does not reduce intake quantity below one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: IntakeReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntakeReviewScreen)),
    );
    container.read(intakeReviewProvider.notifier).seed([
      IntakeProposal(
        id: 'p1',
        name: '苹果',
        quantity: '1',
        unit: '个',
        category: FoodCategories.other,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stepper_minus')).first);
    await tester.pumpAndSettle();

    expect(container.read(intakeReviewProvider).proposals.single.quantity, '1');
  });
}
