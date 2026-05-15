import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tapping 我做了 navigates to DeductionReviewScreen and applies',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final inventory = [
      Ingredient(
        name: '葱', quantity: '3', unit: '把', imageUrl: '',
        freshnessPercent: 1, state: FreshnessState.fresh,
        category: FoodCategories.freshProduce, storage: IconType.fridge,
      ),
    ];
    final recipe = Recipe(
      id: 'r1', name: '葱花蛋', category: '中餐',
      difficulty: 1, cookingMinutes: 10, description: '',
      ingredients: [RecipeIngredient(name: '葱', quantity: '1', unit: '把')],
      steps: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          inventorySeedProvider.overrideWithValue(inventory),
        ],
        child: MaterialApp(home: RecipeDetailScreen(recipe: recipe)),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll until the button is visible
    await tester.scrollUntilVisible(
      find.byKey(const Key('recipe_cooked_action')),
      100,
    );
    await tester.tap(find.byKey(const Key('recipe_cooked_action')));
    await tester.pumpAndSettle();

    expect(find.text('葱'), findsWidgets);
    expect(find.textContaining('确认扣减'), findsOneWidget);

    await tester.tap(find.textContaining('确认扣减'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeDetailScreen)));
    expect(container.read(inventoryProvider).first.quantity, '2',
        reason: '3 - 1 = 2');
  });
}
