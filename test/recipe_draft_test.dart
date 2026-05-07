import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';

void main() {
  test('toRecipe preserves all values', () {
    final draft = RecipeDraft(
      sourceUrl: 'https://lanfanapp.com/recipe/15978',
      name: DraftField.ai('番茄牛腩面'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(60),
      difficulty: DraftField.ai(3),
      description: DraftField.ai('家常做法'),
      imageUrl: DraftField.ai('https://example.com/img.jpg'),
      ingredients: [
        RecipeIngredientDraft(name: DraftField.ai('番茄'), amount: DraftField.ai('2 个')),
      ],
      steps: [DraftField.ai('番茄切块')],
    );

    final recipe = draft.toRecipe(idGenerator: () => 'r-test');
    expect(recipe.id, 'r-test');
    expect(recipe.name, '番茄牛腩面');
    expect(recipe.cookingMinutes, 60);
    expect(recipe.ingredients.single.name, '番茄');
    expect(recipe.steps.single, '番茄切块');
  });
}
