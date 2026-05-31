import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';

/// Compact action chip displayed at the end of a Proposal row. Tapping cycles
/// through allowed actions (Intake: newRow ↔ mergeInto if a target exists;
/// Deduction: deduct ↔ skip). The chip's label and color reflect current state.
class ProposalActionChip extends StatelessWidget {
  const ProposalActionChip.intake({
    super.key,
    required this.intakeAction,
    required this.mergeTargetLabel,
    required this.onToggle,
  }) : deductionAction = null;

  const ProposalActionChip.deduction({
    super.key,
    required this.deductionAction,
    required this.onToggle,
  }) : intakeAction = null,
       mergeTargetLabel = null;

  final IntakeAction? intakeAction;
  final DeductionAction? deductionAction;
  final String? mergeTargetLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _styleFor();
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: AppFontSize.sm,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.keyboard_arrow_down, size: 14, color: fg),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _styleFor() {
    if (intakeAction != null) {
      switch (intakeAction!) {
        case IntakeAction.newRow:
          return (
            '新建 Batch',
            AppColors.primarySoft,
            AppColors.primaryContainer,
          );
        case IntakeAction.mergeInto:
          return (
            mergeTargetLabel == null ? '合并' : '合并 → $mergeTargetLabel',
            AppColors.fkWarnSoft,
            AppColors.onSecondaryContainer,
          );
      }
    }
    switch (deductionAction!) {
      case DeductionAction.deduct:
        return ('扣库存', AppColors.primarySoft, AppColors.primaryContainer);
      case DeductionAction.skip:
        return ('跳过', AppColors.surfaceContainer, AppColors.outline);
    }
  }
}
