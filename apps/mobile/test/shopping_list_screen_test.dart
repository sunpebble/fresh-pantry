import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/recipe_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/shopping_list_screen.dart';
import 'package:fresh_pantry/widgets/shared/cat_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('category headers collapse and expand their shopping items', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
        const ShoppingItem(
          id: 'milk',
          name: '牛奶',
          detail: '',
          category: FoodCategories.dairyAndEggs,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(FoodCategories.freshProduce), findsOneWidget);
    // FK CatIcon replaces the old Material outlined icon.
    expect(find.byType(CatIcon), findsAtLeastNWidgets(1));
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();

    expect(find.text(FoodCategories.freshProduce), findsOneWidget);
    expect(find.text('番茄'), findsNothing);
    expect(find.text('牛奶'), findsOneWidget);

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();

    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('inline X icon on a shopping row deletes it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(body: ShoppingListScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider).single.name, '番茄');

    // FK redesign: each row has an inline X icon for delete.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider), isEmpty);
    expect(find.text('「番茄」已删除'), findsOneWidget);
  });

  testWidgets('top add button focuses the quick add field', (tester) async {
    SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final fieldBefore = tester.widget<EditableText>(find.byType(EditableText));
    expect(fieldBefore.focusNode.hasFocus, isFalse);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    final fieldAfter = tester.widget<EditableText>(find.byType(EditableText));
    expect(fieldAfter.focusNode.hasFocus, isTrue);
  });

  testWidgets('smart planner stays hidden without a suggested recipe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'pasta',
          name: '意大利面',
          detail: '200g',
          category: FoodCategories.other,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          recipesProvider.overrideWith((ref) async => const <Recipe>[]),
        ],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('查看食谱'), findsNothing);
    expect(find.textContaining('卡博纳拉'), findsNothing);
  });

  testWidgets('smart planner view recipe opens the suggested recipe detail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([_ingredient('牛奶').toJson()]),
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'pasta',
          name: '意大利面',
          detail: '200g',
          category: FoodCategories.other,
        ).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          recipesProvider.overrideWith(
            (ref) async => [
              _recipe('recipe-milk', '牛奶早餐杯', ['牛奶']),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ShoppingListScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('查看食谱'), findsOneWidget);

    await tester.tap(find.text('查看食谱'));
    await tester.pumpAndSettle();

    expect(find.text('牛奶早餐杯'), findsOneWidget);
    // FK redesign relabels "所需食材" → "食材清单".
    expect(find.text('食材清单'), findsOneWidget);
  });
}

Ingredient _ingredient(String name) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: FoodCategories.dairyAndEggs,
    storage: IconType.fridge,
  );
}

Recipe _recipe(String id, String name, List<String> ingredients) {
  return Recipe(
    id: id,
    name: name,
    category: '测试',
    difficulty: 1,
    cookingMinutes: 10,
    description: '',
    ingredients: ingredients
        .map((ingredient) => RecipeIngredient(name: ingredient, amount: '1'))
        .toList(),
    steps: const ['完成'],
  );
}
