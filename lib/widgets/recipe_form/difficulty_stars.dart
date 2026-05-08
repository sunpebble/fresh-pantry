import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class DifficultyStars extends StatelessWidget {
  const DifficultyStars({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static const _labels = ['简单', '较易', '普通', '进阶', '专业'];

  String get _label {
    if (value < 1 || value > 5) return '';
    return _labels[value - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          GestureDetector(
            onTap: () => onChanged(i + 1),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                Icons.star_rounded,
                size: 32,
                color: i < value
                    ? AppColors.secondaryContainer
                    : AppColors.surfaceContainerHigh,
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.urgentAttentionBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            _label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}
