import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../utils/safe_push.dart';
import '../widgets/recipe_card.dart';
import 'custom_recipe_detail_screen.dart';
import 'custom_recipe_form_screen.dart';

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
          pushRouteOnce(
            context,
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
                  () => pushRouteOnce(
                    context,
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
    pushRouteOnce(
      context,
      MaterialPageRoute(
        builder: (context) => CustomRecipeDetailScreen(recipeId: recipe.id),
      ),
    );
  }

  Future<void> _handleMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    if (value == 'edit') {
      pushRouteOnce(
        context,
        MaterialPageRoute(
          builder: (context) => CustomRecipeFormScreen(recipe: recipe),
        ),
      );
    }
    if (value == 'delete') {
      final confirmed = await confirmDeleteCustomRecipe(context, recipe);
      if (!confirmed || !context.mounted) {
        return;
      }

      try {
        await ref.read(customRecipesProvider.notifier).remove(recipe.id);
      } on Object {
        if (context.mounted) {
          showCustomRecipeDeleteFailure(context);
        }
      }
    }
  }
}
