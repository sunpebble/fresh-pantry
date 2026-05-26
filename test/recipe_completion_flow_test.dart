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
  testWidgets('recipe detail toggles step progress and hides 0/0 boundary', (
    tester,
  ) async {
    final prefs = await _prefs();
    final recipe = Recipe(
      id: 'steps',
      name: '两步菜',
      category: '中餐',
      difficulty: 1,
      cookingMinutes: 10,
      description: '',
      ingredients: const [],
      steps: const ['切菜', '装盘'],
    );

    await tester.pumpWidget(_app(prefs, RecipeDetailScreen(recipe: recipe)));
    await tester.pumpAndSettle();

    expect(find.text('0/2'), findsOneWidget);
    await tester.tap(find.text('切菜'));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);

    final emptyRecipe = recipe.copyWith(id: 'empty', steps: const []);
    await tester.pumpWidget(
      _app(prefs, RecipeDetailScreen(recipe: emptyRecipe)),
    );
    await tester.pumpAndSettle();

    expect(find.text('0/0'), findsNothing);
    expect(find.text('烹饪步骤'), findsOneWidget);
  });

  testWidgets('tapping 我做了 navigates to DeductionReviewScreen and applies', (
    tester,
  ) async {
    final prefs = await _prefs();
    final inventory = [
      Ingredient(
        name: '葱',
        quantity: '3',
        unit: '把',
        imageUrl: '',
        freshnessPercent: 1,
        state: FreshnessState.fresh,
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
      ),
    ];
    final recipe = Recipe(
      id: 'r1',
      name: '葱花蛋',
      category: '中餐',
      difficulty: 1,
      cookingMinutes: 10,
      description: '',
      ingredients: [RecipeIngredient(name: '葱', quantity: '1', unit: '把')],
      steps: const [],
    );

    await tester.pumpWidget(
      _app(prefs, RecipeDetailScreen(recipe: recipe), inventory: inventory),
    );
    await tester.pumpAndSettle();

    // Scroll until the button is visible
    await tester.scrollUntilVisible(
      find.byKey(const Key('recipe_cooked_action')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('recipe_cooked_action')));
    await tester.pumpAndSettle();

    expect(find.text('葱'), findsWidgets);
    expect(find.textContaining('确认扣减'), findsOneWidget);

    await tester.tap(find.textContaining('确认扣减'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecipeDetailScreen)),
    );
    expect(
      container.read(inventoryProvider).first.quantity,
      '2',
      reason: '3 - 1 = 2',
    );
  });
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _app(
  SharedPreferences prefs,
  Widget child, {
  List<Ingredient> inventory = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(inventory),
    ],
    child: MaterialApp(theme: ThemeData(useMaterial3: false), home: child),
  );
}
