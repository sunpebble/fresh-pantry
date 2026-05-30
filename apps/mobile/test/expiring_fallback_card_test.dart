import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/widgets/dashboard/expiring_fallback_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Ingredient _ing({required String name, FreshnessState? state}) => Ingredient(
  name: name,
  quantity: '1',
  unit: '个',
  imageUrl: '',
  freshnessPercent: state == FreshnessState.expiringSoon ? 0.2 : 1.0,
  state: state ?? FreshnessState.fresh,
  category: FoodCategories.other,
  storage: IconType.fridge,
);

Recipe _recipe(String id, List<String> ings) => Recipe(
  id: id,
  name: id,
  category: '中餐',
  difficulty: 1,
  cookingMinutes: 10,
  description: '',
  ingredients:
      ings
          .map((n) => RecipeIngredient(name: n, quantity: '1', unit: '个'))
          .toList(),
  steps: const [],
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = newTestDatabase();
    addTearDown(db.close);
  });

  testWidgets('renders SizedBox.shrink when no fallback', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          inventorySeedProvider.overrideWithValue([_ing(name: '苹果')]),
          recipesProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(home: Scaffold(body: ExpiringFallbackCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('用临期食材'), findsNothing);
  });

  testWidgets('renders recipe name + coverage when fallback exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          inventorySeedProvider.overrideWithValue([
            _ing(name: '番茄', state: FreshnessState.expiringSoon),
            _ing(name: '鸡蛋', state: FreshnessState.expiringSoon),
          ]),
          recipesProvider.overrideWith(
            (ref) => Future.value([
              _recipe('番茄炒蛋', ['番茄', '鸡蛋']),
            ]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ExpiringFallbackCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用临期食材'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('可用 2 件临期食材'), findsOneWidget);
  });
}
