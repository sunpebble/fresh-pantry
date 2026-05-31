import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/widgets/inventory/ingredient_card.dart';

void main() {
  const ingredient = Ingredient(
    name: '番茄',
    quantity: '2',
    unit: '个',
    imageUrl: '',
    freshnessPercent: 0.9,
    state: FreshnessState.fresh,
    category: FoodCategories.freshProduce,
    storage: IconType.fridge,
  );

  testWidgets('IngredientCard wraps icon in a Hero when heroTag is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IngredientCard(
            ingredient: ingredient,
            heroTag: 'ingredient-image-test',
          ),
        ),
      ),
    );
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'ingredient-image-test');
  });

  testWidgets('IngredientCard has no Hero when heroTag is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IngredientCard(ingredient: ingredient)),
      ),
    );
    expect(find.byType(Hero), findsNothing);
  });
}
