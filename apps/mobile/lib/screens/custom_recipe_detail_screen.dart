import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/page_transitions.dart';
import 'custom_recipe_form_screen.dart';
import 'recipe_detail_screen.dart';

class CustomRecipeDetailScreen extends ConsumerWidget {
  const CustomRecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(customRecipesProvider);
    Recipe? latestRecipe;
    for (final recipe in recipes) {
      if (recipe.id == recipeId) {
        latestRecipe = recipe;
        break;
      }
    }

    if (latestRecipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('食谱已删除')),
      );
    }

    return RecipeDetailScreen(
      recipe: latestRecipe,
      isCustomRecipe: true,
      onEdit: () {
        Navigator.of(context).push(
          fkRoute<void>(
            builder: (context) => CustomRecipeFormScreen(recipe: latestRecipe),
          ),
        );
      },
      onDelete: () async {
        final confirmed = await confirmDeleteCustomRecipe(
          context,
          latestRecipe!,
        );
        if (!confirmed || !context.mounted) {
          return;
        }

        try {
          await ref.read(customRecipesProvider.notifier).remove(recipeId);
        } on Object {
          if (context.mounted) {
            showCustomRecipeDeleteFailure(context);
          }
          return;
        }

        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }
}

Future<bool> confirmDeleteCustomRecipe(BuildContext context, Recipe recipe) {
  return showAppConfirmDialog(
    context,
    title: '删除食谱',
    content: '确定要删除“${recipe.name}”吗？此操作无法撤销。',
    confirmLabel: '删除',
    isDestructive: true,
  );
}

void showCustomRecipeDeleteFailure(BuildContext context) {
  showAppSnackBar(context, '删除失败，请重试');
}
