import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../widgets/recipe_card.dart';
import 'custom_recipe_form_screen.dart';
import 'recipe_detail_screen.dart';

class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(customRecipesProvider);
    ref.watch(inventoryProvider.select(inventoryNamesSignature));
    final inventoryNames = inventoryNameSet(ref.read(inventoryProvider));

    return Scaffold(
      appBar: AppBar(title: const Text('我的食谱')),
      body:
          recipes.isEmpty
              ? const _EmptyMyRecipesState()
              : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  return _MyRecipeCard(
                    recipe: recipe,
                    matchedCount: matchedIngredientCountForNames(
                      inventoryNames,
                      recipe,
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CustomRecipeFormScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('新建食谱'),
      ),
    );
  }
}

class _EmptyMyRecipesState extends StatelessWidget {
  const _EmptyMyRecipesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 52,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '还没有自定义食谱',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '保存家常菜、备餐组合或临期清库存做法。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CustomRecipeFormScreen(),
                    ),
                  ),
              icon: const Icon(Icons.add),
              label: const Text('创建第一份食谱'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRecipeCard extends ConsumerWidget {
  const _MyRecipeCard({required this.recipe, required this.matchedCount});

  final Recipe recipe;
  final int matchedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle =
        recipe.description.isNotEmpty ? recipe.description : recipe.category;

    return RecipeCard(
      recipe: recipe,
      subtitle: subtitle,
      matchedCount: matchedCount,
      onTap: () => _openRecipe(context),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: PopupMenuButton<String>(
          tooltip: '食谱操作',
          onSelected: (value) => _handleMenuSelection(context, ref, value),
          itemBuilder:
              (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
        ),
      ),
    );
  }

  void _openRecipe(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _CustomRecipeDetailRoute(recipeId: recipe.id),
      ),
    );
  }

  Future<void> _handleMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'edit') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CustomRecipeFormScreen(recipe: recipe),
        ),
      );
    }
    if (value == 'delete') {
      final confirmed = await _confirmDeleteRecipe(context, recipe);
      if (!confirmed || !context.mounted) {
        return;
      }

      try {
        await ref.read(customRecipesProvider.notifier).remove(recipe.id);
      } on Object {
        if (context.mounted) {
          _showDeleteFailure(context);
        }
      }
    }
  }
}

class _CustomRecipeDetailRoute extends ConsumerWidget {
  const _CustomRecipeDetailRoute({required this.recipeId});

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
          MaterialPageRoute(
            builder: (context) => CustomRecipeFormScreen(recipe: latestRecipe),
          ),
        );
      },
      onDelete: () async {
        final confirmed = await _confirmDeleteRecipe(context, latestRecipe!);
        if (!confirmed || !context.mounted) {
          return;
        }

        try {
          await ref.read(customRecipesProvider.notifier).remove(recipeId);
        } on Object {
          if (context.mounted) {
            _showDeleteFailure(context);
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

Future<bool> _confirmDeleteRecipe(BuildContext context, Recipe recipe) {
  return showAppConfirmDialog(
    context,
    title: '删除食谱',
    content: '确定要删除“${recipe.name}”吗？此操作无法撤销。',
    confirmLabel: '删除',
    isDestructive: true,
  );
}

void _showDeleteFailure(BuildContext context) {
  showAppSnackBar(context, '删除失败，请重试');
}
