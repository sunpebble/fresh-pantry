import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';
import '../shared/category_icon.dart';

class RecentAdditionItem extends StatelessWidget {
  final Ingredient item;

  const RecentAdditionItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            CategoryIconAvatar(category: item.category, size: 64, iconSize: 30),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _addedAtLabel(item.addedAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.quantity} ${item.unit}'.trim(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: item.freshnessPercent,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _addedAtLabel(DateTime? addedAt) {
    if (addedAt == null) return '最近添加';

    var elapsed = DateTime.now().difference(addedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;

    if (elapsed.inMinutes < 1) return '刚刚添加';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}分钟前添加';
    if (elapsed.inHours < 24) return '${elapsed.inHours}小时前添加';
    if (elapsed.inHours < 48) return '昨天添加';
    return '${elapsed.inDays}天前添加';
  }
}
