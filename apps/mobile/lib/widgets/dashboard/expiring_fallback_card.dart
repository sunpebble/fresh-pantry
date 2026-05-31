import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/recipe_provider.dart';
import '../../screens/recipe_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/page_transitions.dart';
import '../shared/fk_card.dart';
import '../shared/pill_chip.dart';
import '../shared/recipe_image.dart';

class ExpiringFallbackCard extends ConsumerWidget {
  const ExpiringFallbackCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(expiringFallbackRecipeProvider);
    if (result == null) return const SizedBox.shrink();
    final recipe = result.recipe;
    final covered = result.coveredExpiringNames;

    return FkCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(
        context,
      ).push(fkRoute<void>(builder: (_) => RecipeDetailScreen(recipe: recipe))),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.xl),
                bottomLeft: Radius.circular(AppRadius.xl),
              ),
              child: SizedBox(
                width: 96,
                child: RecipeImage(
                  imageSource: recipe.imageUrl,
                  fit: BoxFit.cover,
                  fallback: Container(
                    color: AppColors.fkWarnSoft,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.local_fire_department,
                      color: AppColors.fkWarn,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '用临期食材',
                          style: TextStyle(
                            fontSize: AppFontSize.xs,
                            fontWeight: FontWeight.w600,
                            color: AppColors.fkWarn,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          recipe.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppFontSize.lg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '可用 ${covered.length} 件临期食材',
                          style: const TextStyle(
                            fontSize: AppFontSize.sm,
                            color: AppColors.outline,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: covered
                              .take(3)
                              .map(
                                (name) => PillChip(
                                  label: name,
                                  backgroundColor: AppColors.fkWarnSoft,
                                  foregroundColor:
                                      AppColors.onSecondaryContainer,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
