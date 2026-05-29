import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/recipe_provider.dart';
import '../../screens/recipe_detail_screen.dart';
import '../../theme/app_theme.dart';
import '../shared/fk_card.dart';
import '../shared/pill_chip.dart';

class ExpiringFallbackCard extends ConsumerWidget {
  const ExpiringFallbackCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(expiringFallbackRecipeProvider);
    if (result == null) return const SizedBox.shrink();
    final recipe = result.recipe;
    final covered = result.coveredExpiringNames;

    return FkCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.fkWarnSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: AppColors.fkWarn,
              size: 36,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '用临期食材',
                  style: TextStyle(
                    fontSize: 11,
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可用 ${covered.length} 件临期食材',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: covered
                      .take(3)
                      .map((name) => PillChip(
                            label: name,
                            backgroundColor: AppColors.fkWarnSoft,
                            foregroundColor: AppColors.onSecondaryContainer,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
