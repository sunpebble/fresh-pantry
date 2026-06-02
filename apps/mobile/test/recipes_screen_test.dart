import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
import 'package:fresh_pantry/screens/recipes_screen.dart';
import 'package:fresh_pantry/storage/local_recipe_repository.dart';
import 'package:fresh_pantry/widgets/shared/fk_skeleton_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

void main() {
  testWidgets('recipes screen add button opens custom recipe form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // RecipesScreen watches recipesFetchProvider; without this override it
          // would hit the real rootBundle asset and stall pumpAndSettle.
          localRecipeRepositoryProvider.overrideWithValue(
            LocalRecipeRepository(loadString: (_) async => '[]'),
          ),
          ...testStorageOverrides(
            database: db,
            inventory: const <Ingredient>[],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: RecipesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(CustomRecipeFormScreen), findsOneWidget);
    expect(find.text('保存食谱'), findsOneWidget);
  });

  testWidgets('explore tab shows recipe loading skeleton', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final pendingRecipes = Completer<List<Recipe>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // RecipesScreen watches recipesFetchProvider; without this override it
          // would hit the real rootBundle asset and stall pumpAndSettle.
          localRecipeRepositoryProvider.overrideWithValue(
            LocalRecipeRepository(loadString: (_) async => '[]'),
          ),
          ...testStorageOverrides(
            database: db,
            inventory: const <Ingredient>[],
          ),
          recipesProvider.overrideWith((ref) => pendingRecipes.future),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: RecipesScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('探索'));
    await tester.pump();

    expect(find.byType(FkRecipeSkeletonCard), findsNWidgets(3));
    expect(find.text('暂无可探索的菜谱'), findsNothing);
  });

  testWidgets('mine tab lists saved custom recipes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // RecipesScreen watches recipesFetchProvider; without this override it
          // would hit the real rootBundle asset and stall pumpAndSettle.
          localRecipeRepositoryProvider.overrideWithValue(
            LocalRecipeRepository(loadString: (_) async => '[]'),
          ),
          ...testStorageOverrides(
            database: db,
            inventory: const <Ingredient>[],
            customRecipes: [
              Recipe(
                id: 'custom_1',
                name: '我的番茄面',
                category: '家常',
                difficulty: 2,
                cookingMinutes: 20,
                description: '',
                ingredients: [RecipeIngredient(name: '番茄', amount: '2个')],
                steps: ['煮面'],
                tags: [],
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: RecipesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('我的番茄面'), findsOneWidget);
  });
}
