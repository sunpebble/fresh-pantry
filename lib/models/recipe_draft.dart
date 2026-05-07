import 'package:flutter/foundation.dart';

import 'draft_field.dart';
import 'recipe.dart';

@immutable
class RecipeIngredientDraft {
  const RecipeIngredientDraft({required this.name, required this.amount});
  final DraftField<String> name;
  final DraftField<String> amount;

  RecipeIngredient toIngredient() =>
      RecipeIngredient(name: name.value, amount: amount.value);
}

@immutable
class RecipeDraft {
  const RecipeDraft({
    required this.sourceUrl,
    required this.name,
    required this.category,
    required this.cookingMinutes,
    required this.difficulty,
    required this.description,
    required this.imageUrl,
    required this.ingredients,
    required this.steps,
  });

  final String? sourceUrl;
  final DraftField<String> name;
  final DraftField<String> category;
  final DraftField<int> cookingMinutes;
  final DraftField<int> difficulty;
  final DraftField<String> description;
  final DraftField<String?> imageUrl;
  final List<RecipeIngredientDraft> ingredients;
  final List<DraftField<String>> steps;

  Recipe toRecipe({String Function()? idGenerator}) {
    final id =
        idGenerator?.call() ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    return Recipe(
      id: id,
      name: name.value,
      category: category.value,
      difficulty: difficulty.value,
      cookingMinutes: cookingMinutes.value,
      description: description.value,
      imageUrl: imageUrl.value,
      ingredients: ingredients.map((i) => i.toIngredient()).toList(),
      steps: steps.map((s) => s.value).toList(),
      tags: const [],
    );
  }
}
