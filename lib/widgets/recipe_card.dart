import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import 'shared/fk_card.dart';
import 'shared/fk_pill.dart';
import 'shared/recipe_image.dart';

/// 设计稿 `screens-3.jsx::RecipeCard` — 横向卡片:左 120px 方形封面图 + 右侧
/// 内容区(名称 / 时间·难度 / 食材匹配进度条 / 标签 pills)。
///
/// 进度条颜色根据匹配比例:满 = primary,≥0.7 = primaryLight,否则 warn(黄油黄)。
/// `useExpiring=true` 时左上叠"临期"角标(黄油黄底)。
class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final int? matchedCount;
  final String? subtitle;
  final String? ingredientLabel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool useExpiring;

  const RecipeCard({
    super.key,
    required this.recipe,
    this.matchedCount,
    this.subtitle,
    this.ingredientLabel,
    this.trailing,
    this.onTap,
    this.useExpiring = false,
  });

  @override
  Widget build(BuildContext context) {
    final total = recipe.ingredients.length;
    final matched = matchedCount ?? 0;
    final missing = (total - matched).clamp(0, total);
    final ratio = total == 0 ? 0.0 : matched / total;
    final progressColor = ratio >= 1.0
        ? AppColors.primary
        : ratio >= 0.7
        ? AppColors.primaryLight
        : AppColors.fkWarn;

    return Semantics(
      button: onTap != null,
      label: recipe.name,
      child: FkCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cover(recipe: recipe, useExpiring: useExpiring),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DefaultTextStyle.merge(
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                              height: 1.2,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 11,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Text('${recipe.cookingMinutes} 分钟'),
                                const SizedBox(width: 10),
                                Text('· ${recipe.difficultyLabel}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                ingredientLabel ?? '食材匹配 $matched/$total',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              const Spacer(),
                              if (missing > 0)
                                Text(
                                  '缺 $missing 件',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.fkDanger,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: ratio.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: progressColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          if (recipe.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 22,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final tag in recipe.tags.take(2)) ...[
                                    FkPill(label: tag, sm: true),
                                    const SizedBox(width: 4),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final Recipe recipe;
  final bool useExpiring;
  const _Cover({required this.recipe, required this.useExpiring});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.xl),
              bottomLeft: Radius.circular(AppRadius.xl),
            ),
            child: RecipeImage(
              imageSource: recipe.imageUrl,
              fit: BoxFit.cover,
              fallback: Container(
                color: AppColors.primarySoft,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.restaurant_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          if (useExpiring)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.fkWarn,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '临期',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
