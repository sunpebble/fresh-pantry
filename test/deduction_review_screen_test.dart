import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/providers/deduction_review_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/deduction_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders proposals and confirm button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: DeductionReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DeductionReviewScreen)));
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
}
