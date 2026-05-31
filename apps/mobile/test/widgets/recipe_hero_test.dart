import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/widgets/recipe_card.dart';

void main() {
  testWidgets('RecipeCard wraps cover in a Hero when heroTag is set', (
    tester,
  ) async {
    final recipe = Recipe(
      id: 'r1',
      name: '番茄炒蛋',
      category: '家常菜',
      difficulty: 1,
      cookingMinutes: 10,
      description: '',
      ingredients: const [],
      steps: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCard(recipe: recipe, heroTag: 'recipe-image-r1'),
        ),
      ),
    );
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'recipe-image-r1');
  });

  testWidgets('RecipeCard has no Hero when heroTag is null', (tester) async {
    final recipe = Recipe(
      id: 'r2',
      name: '青椒土豆丝',
      category: '家常菜',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: const [],
      steps: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecipeCard(recipe: recipe)),
      ),
    );
    expect(find.byType(Hero), findsNothing);
  });
}
