import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';

class FreshnessMeter extends StatelessWidget {
  final double percent;
  final FreshnessState state;
  final bool showLabel;

  const FreshnessMeter({
    super.key,
    required this.percent,
    required this.state,
    this.showLabel = true,
  });

  Color get _barColor {
    switch (state) {
      case FreshnessState.fresh:
        return AppColors.primary;
      case FreshnessState.expiringSoon:
        return AppColors.secondary;
      case FreshnessState.expired:
        return AppColors.error;
    }
  }

  String get _label {
    switch (state) {
      case FreshnessState.fresh:
        return '新鲜度 ${(percent * 100).round()}%';
      case FreshnessState.expiringSoon:
        return '剩余 ${(percent * 100).round()}%';
      case FreshnessState.expired:
        return '新鲜度 0%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(_barColor),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '新鲜度指标',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                _label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _barColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class GradientFreshnessMeter extends StatelessWidget {
  final double percent;

  const GradientFreshnessMeter({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '最佳新鲜',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            Text(
              '即将到期',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percent,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.tertiaryFixedDim,
                          AppColors.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
