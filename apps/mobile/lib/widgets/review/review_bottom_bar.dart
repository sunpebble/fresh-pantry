import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ReviewBottomBar extends StatelessWidget {
  const ReviewBottomBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onToggleSelectAll,
    this.onCancel,
  });

  final int selectedCount;
  final int totalCount;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == totalCount && totalCount > 0;
    final canToggleSelection = totalCount > 0;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: canToggleSelection ? onToggleSelectAll : null,
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              size: 18,
            ),
            label: Text(allSelected ? '取消全选' : '全选'),
          ),
          const Spacer(),
          if (onCancel != null) ...[
            OutlinedButton(onPressed: onCancel, child: const Text('取消')),
            const SizedBox(width: AppSpacing.sm),
          ],
          FilledButton(
            onPressed: selectedCount == 0 ? null : onConfirm,
            child: Text('$confirmLabel ($selectedCount)'),
          ),
        ],
      ),
    );
  }
}
