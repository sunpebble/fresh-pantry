import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/food_knowledge.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../providers/deduction_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../providers/shopping_provider.dart';
import '../services/deduction_proposal_factory.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/recipe_image.dart';
import 'deduction_review_screen.dart';

/// 设计稿 `screens-3.jsx::RecipeDetailScreen`。
///
/// 视觉栈:大 hero 图(260px)+ 浮 back/收藏 → 标题 + 时间/难度 + 标签 →
/// 食材清单(缺少项 dangerSoft 高亮 + dashed border)→ 一键加购缺少 CTA →
/// 步骤卡(圆形 step number + 可点完成切换)→ 底部 "开始烹饪" primary CTA。
class RecipeDetailScreen extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isCustomRecipe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    this.isCustomRecipe = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  final Set<int> _completedSteps = <int>{};
  bool _isFavorite = false;

  @override
  void didUpdateWidget(covariant RecipeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe.id != widget.recipe.id ||
        !listEquals(oldWidget.recipe.steps, widget.recipe.steps)) {
      _completedSteps.clear();
    }
  }

  void _toggleStep(int index) {
    setState(() {
      if (_completedSteps.contains(index)) {
        _completedSteps.remove(index);
      } else {
        _completedSteps.add(index);
      }
    });
  }

  Future<void> _addMissingToCart(List<RecipeIngredient> missing) async {
    var addedCount = 0;
    for (final ing in missing) {
      final added = await ref
          .read(shoppingProvider.notifier)
          .add(
            ShoppingItem(
              id: '${ShoppingItem.newId()}_${ing.name}',
              name: ing.name,
              detail: ing.amount,
              category: FoodKnowledge.categoryFor(ing.name),
            ),
          );
      if (added) addedCount++;
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      addedCount == 0 ? '缺失食材已在购物清单中' : '已将 $addedCount 个食材加入购物清单',
      backgroundColor: addedCount == 0 ? AppColors.tertiary : AppColors.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(inventoryProvider.select(inventoryNamesSignature));
    final inventoryNames = inventoryNameSet(ref.read(inventoryProvider));
    final matched = matchedIngredientCountForNames(
      inventoryNames,
      widget.recipe,
    );
    final missing = missingRecipeIngredientsForNames(
      inventoryNames,
      widget.recipe,
    );

    final stepProgress =
        widget.recipe.steps.isEmpty
            ? 0.0
            : _completedSteps.length / widget.recipe.steps.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HeroSection(
            recipe: widget.recipe,
            isFavorite: _isFavorite,
            isCustom: widget.isCustomRecipe,
            onBack: () => Navigator.of(context).maybePop(),
            onToggleFavorite: () => setState(() => _isFavorite = !_isFavorite),
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipe.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                DefaultTextStyle.merge(
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text('${widget.recipe.cookingMinutes} 分钟'),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.local_fire_department_outlined,
                        size: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(widget.recipe.difficultyLabel),
                    ],
                  ),
                ),
                if (widget.recipe.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    widget.recipe.description,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.recipe.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in widget.recipe.tags)
                        FkPill(
                          label: tag,
                          backgroundColor: AppColors.primarySoft,
                          foregroundColor: AppColors.primaryContainer,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                _IngredientsSection(
                  recipe: widget.recipe,
                  inventoryNames: inventoryNames,
                  matched: matched,
                  missingCount: missing.length,
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _AddMissingCta(
                    count: missing.length,
                    onTap: () => _addMissingToCart(missing),
                  ),
                ],
                const SizedBox(height: 24),
                _StepsSection(
                  steps: widget.recipe.steps,
                  completed: _completedSteps,
                  progress: stepProgress,
                  onToggleStep: _toggleStep,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('recipe_cooked_action'),
                  icon: const Icon(Icons.restaurant),
                  label: const Text('我做了'),
                  onPressed: () async {
                    final inv = ref.read(inventoryProvider);
                    final proposals = DeductionProposalFactory.forRecipe(
                      widget.recipe,
                      inv,
                    );
                    ref.read(deductionReviewProvider.notifier).seed(proposals);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeductionReviewScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _StartCookingButton(onTap: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final Recipe recipe;
  final bool isFavorite;
  final bool isCustom;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _HeroSection({
    required this.recipe,
    required this.isFavorite,
    required this.isCustom,
    required this.onBack,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenHeight * 0.32).clamp(200.0, 260.0);
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RecipeImage(
            imageSource: recipe.imageUrl,
            fit: BoxFit.cover,
            semanticLabel: recipe.name,
            fallback: Container(
              color: AppColors.primarySoft,
              alignment: Alignment.center,
              child: const Icon(
                Icons.restaurant_rounded,
                size: 64,
                color: AppColors.primary,
              ),
            ),
          ),
          // Top scrim so floating chrome stays readable on dark covers
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: MediaQuery.of(context).padding.top + 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  FkIconButton(
                    onTap: onBack,
                    onImage: true,
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  if (isCustom && onEdit != null) ...[
                    Tooltip(
                      message: '编辑食谱',
                      child: FkIconButton(
                        onTap: onEdit!,
                        onImage: true,
                        child: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isCustom && onDelete != null) ...[
                    Tooltip(
                      message: '删除食谱',
                      child: FkIconButton(
                        onTap: onDelete!,
                        onImage: true,
                        foregroundColor: AppColors.fkDanger,
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FkIconButton(
                    onTap: onToggleFavorite,
                    onImage: true,
                    foregroundColor:
                        isFavorite ? AppColors.fkDanger : AppColors.onSurface,
                    child: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_outline_rounded,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientsSection extends StatelessWidget {
  final Recipe recipe;
  final Set<String> inventoryNames;
  final int matched;
  final int missingCount;

  const _IngredientsSection({
    required this.recipe,
    required this.inventoryNames,
    required this.matched,
    required this.missingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '食材清单',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '已有 $matched/${recipe.ingredients.length}',
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FkCard(
          padding: EdgeInsets.zero,
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recipe.ingredients.length,
            itemBuilder: (context, index) {
              final ingredient = recipe.ingredients[index];
              return _IngredientRow(
                index: index,
                ingredient: ingredient,
                isAvailable: recipeIngredientMatchesInventory(
                  ingredient,
                  inventoryNames,
                ),
                isLast: index == recipe.ingredients.length - 1,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final int index;
  final RecipeIngredient ingredient;
  final bool isAvailable;
  final bool isLast;

  const _IngredientRow({
    required this.index,
    required this.ingredient,
    required this.isAvailable,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('ingredient_$index'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.transparent : AppColors.fkDangerSoft,
        border:
            isLast
                ? null
                : const Border(
                  bottom: BorderSide(color: AppColors.hair, width: 0.5),
                ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StatusMark(isAvailable: isAvailable),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        isAvailable ? AppColors.onSurface : AppColors.fkDanger,
                  ),
                ),
                if (ingredient.amount.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ingredient.amount,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          isAvailable
              ? FkPill(
                label: '已有',
                sm: true,
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.primaryContainer,
              )
              : FkPill(
                label: '缺少',
                sm: true,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.fkDanger,
                border: const BorderSide(
                  color: AppColors.fkDanger,
                  width: 1,
                  style: BorderStyle.solid,
                ),
              ),
        ],
      ),
    );
  }
}

class _StatusMark extends StatelessWidget {
  final bool isAvailable;
  const _StatusMark({required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isAvailable ? AppColors.primary : Colors.white,
        shape: BoxShape.circle,
        border:
            isAvailable
                ? null
                : Border.all(color: AppColors.fkDanger, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(
        isAvailable ? Icons.check_rounded : Icons.close_rounded,
        size: isAvailable ? 14 : 12,
        color: isAvailable ? Colors.white : AppColors.fkDanger,
      ),
    );
  }
}

class _AddMissingCta extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AddMissingCta({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '一键加购缺少的 $count 件',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                size: 16,
                color: AppColors.primaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                '一键加购缺少的 $count 件',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  final List<String> steps;
  final Set<int> completed;
  final double progress;
  final void Function(int) onToggleStep;

  const _StepsSection({
    required this.steps,
    required this.completed,
    required this.progress,
    required this.onToggleStep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '烹饪步骤',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const Spacer(),
            if (steps.isNotEmpty)
              Text(
                '${completed.length}/${steps.length}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceContainer,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 12),
        ] else
          const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: steps.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder:
              (_, index) => _StepRow(
                index: index,
                text: steps[index],
                completed: completed.contains(index),
                onTap: () => onToggleStep(index),
              ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String text;
  final bool completed;
  final VoidCallback onTap;

  const _StepRow({
    required this.index,
    required this.text,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FkCard(
      key: ValueKey('step_$index'),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: completed ? AppColors.primary : AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                completed
                    ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                    : Text(
                      '${index + 1}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryContainer,
                      ),
                    ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.5,
                  color:
                      completed
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartCookingButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StartCookingButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowWarm,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.restaurant_menu_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              '开始烹饪',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
