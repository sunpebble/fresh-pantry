import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:fresh_pantry/widgets/shared/fk_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  testWidgets(
    'ingredient card has no safe-area gap above the first row',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      final recipe = Recipe(
        id: 'r1',
        name: '醋溜娃娃菜',
        category: '中餐',
        difficulty: 3,
        cookingMinutes: 10,
        description: '',
        ingredients: [
          RecipeIngredient(name: '娃娃菜', quantity: '2', unit: '颗'),
          RecipeIngredient(name: '五花肉', quantity: '300', unit: 'g'),
        ],
        steps: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db, inventory: const []),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: false),
            // Simulate a device with a non-zero top safe-area (status bar).
            home: MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(top: 50)),
              child: RecipeDetailScreen(recipe: recipe),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardFinder = find.ancestor(
        of: find.byKey(const ValueKey('ingredient_0')),
        matching: find.byType(FkCard),
      );
      final cardTop = tester.getTopLeft(cardFinder).dy;
      final firstRowTop = tester
          .getTopLeft(find.byKey(const ValueKey('ingredient_0')))
          .dy;

      // The card uses zero padding, so the first row must sit flush against the
      // card top — no blank strip injected by the nested ListView's auto safe
      // -area padding.
      expect(firstRowTop - cardTop, lessThan(1.0));
    },
  );
}
