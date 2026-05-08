import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecipeFormCard extends StatelessWidget {
  const RecipeFormCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.countLabel,
    this.iconBackgroundColor,
    this.iconForegroundColor,
    this.hasError = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? countLabel;
  final Color? iconBackgroundColor;
  final Color? iconForegroundColor;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final iconBg = iconBackgroundColor ?? AppColors.primaryFixed;
    final iconFg = iconForegroundColor ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: hasError ? AppColors.error : AppColors.outlineVariant,
          width: hasError ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconFg),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (countLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    countLabel!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
