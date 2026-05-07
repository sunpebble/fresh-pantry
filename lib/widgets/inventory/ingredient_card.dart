import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';
import '../../utils/storage_labels.dart';
import '../shared/category_icon.dart';
import '../shared/freshness_meter.dart';

class IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback? onBuyAgain;
  final VoidCallback? onTap;

  const IngredientCard({
    super.key,
    required this.ingredient,
    this.onBuyAgain,
    this.onTap,
  });

  Color get _badgeBg {
    switch (ingredient.state) {
      case FreshnessState.fresh:
        return AppColors.primaryFixed;
      case FreshnessState.expiringSoon:
        return AppColors.secondaryContainer;
      case FreshnessState.expired:
        return AppColors.errorContainer;
    }
  }

  Color get _badgeText {
    switch (ingredient.state) {
      case FreshnessState.fresh:
        return AppColors.primary;
      case FreshnessState.expiringSoon:
        return AppColors.onSecondaryContainer;
      case FreshnessState.expired:
        return AppColors.onErrorContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = ingredient.state == FreshnessState.expired;

    final cardContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: isExpired ? 0.6 : 1.0,
                child: CategoryIconAvatar(
                  category: ingredient.category,
                  size: 80,
                  iconSize: 34,
                  muted: isExpired,
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            ingredient.name,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface.withValues(
                                alpha: isExpired ? 0.6 : 1.0,
                              ),
                            ),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.outline,
                            size: 20,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ingredient.quantity} \u2022 ${ingredient.unit}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant.withValues(
                          alpha: isExpired ? 0.6 : 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (ingredient.expiryLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _badgeBg,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              ingredient.expiryLabel!.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _badgeText,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                storageIconFor(ingredient.storage),
                                size: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                storageLabelFor(ingredient.storage),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FreshnessMeter(
            percent: ingredient.freshnessPercent,
            state: ingredient.state,
          ),
          if (onBuyAgain != null &&
              ingredient.state != FreshnessState.fresh) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onBuyAgain,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.replay,
                      size: 16,
                      color: AppColors.onSecondaryContainer,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '再买一次',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cardContent,
      );
    }
    return cardContent;
  }
}
