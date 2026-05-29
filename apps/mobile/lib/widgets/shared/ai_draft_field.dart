import 'package:flutter/material.dart';

import '../../models/draft_field.dart';
import '../../theme/app_theme.dart';

typedef DraftEditorBuilder<T> = Widget Function(T initial, void Function(T) save);

class AiDraftFieldChip<T> extends StatelessWidget {
  const AiDraftFieldChip({
    super.key,
    required this.label,
    required this.field,
    required this.onChanged,
    this.formatter,
    this.editorBuilder,
  });

  final String label;
  final DraftField<T> field;
  final ValueChanged<DraftField<T>> onChanged;
  final String Function(T value)? formatter;
  final DraftEditorBuilder<T>? editorBuilder;

  @override
  Widget build(BuildContext context) {
    final isAi = field.source == DraftSource.ai;
    final accent = isAi ? AppColors.aiAccent : AppColors.aiAccentMuted;
    final display = formatter?.call(field.value) ?? '${field.value}';

    return InkWell(
      onTap: () => _openEditor(context),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: TextStyle(fontSize: AppFontSize.xs, color: accent, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (isAi)
                  Text('AI 填', style: TextStyle(fontSize: AppFontSize.xs, color: accent, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(display, style: const TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    if (editorBuilder == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: editorBuilder!(field.value, (next) {
          onChanged(field.editedTo(next));
          Navigator.of(ctx).pop();
        }),
      ),
    );
  }
}
