import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';
import 'action_chip.dart';
import 'inline_number_stepper.dart';
import 'picker_sheet.dart';

class DeductionProposalRow extends StatelessWidget {
  const DeductionProposalRow({
    super.key,
    required this.proposal,
    required this.onToggleSelected,
    required this.onToggleAction,
    required this.onChooseCandidate,
    required this.onChangeAmount,
  });

  final DeductionProposal proposal;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleAction;
  final ValueChanged<int> onChooseCandidate;
  final ValueChanged<String> onChangeAmount;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final chosen = p.candidates.firstWhere(
      (c) => c.inventoryRowIndex == p.chosenIndex,
      orElse:
          () =>
              p.candidates.isEmpty
                  ? const DeductionCandidate(
                    inventoryRowIndex: -1,
                    displayLabel: '',
                  )
                  : p.candidates.first,
    );
    final isSkip = p.action == DeductionAction.skip;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isSkip
                ? AppColors.surfaceContainerLow
                : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onToggleSelected,
                child: Icon(
                  p.selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: p.selected ? AppColors.primary : AppColors.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.recipeIngredientName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (p.requiredQty.isNotEmpty)
                      Text(
                        '菜谱需要 ${p.requiredQty}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.outline,
                        ),
                      ),
                  ],
                ),
              ),
              ProposalActionChip.deduction(
                deductionAction: p.action,
                onToggle: onToggleAction,
              ),
            ],
          ),
          if (!isSkip && p.candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await PickerSheet.show<int>(
                  context,
                  title: '扣减来源批次',
                  options:
                      p.candidates
                          .map(
                            (c) => PickerOption(
                              value: c.inventoryRowIndex,
                              label: c.displayLabel,
                            ),
                          )
                          .toList(),
                  selected: p.chosenIndex,
                );
                if (picked != null) onChooseCandidate(picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: AppColors.onSurface,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        chosen.inventoryRowIndex == -1
                            ? '无可用批次'
                            : chosen.displayLabel,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Icon(
                      Icons.unfold_more,
                      size: 16,
                      color: AppColors.outline,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  '扣减',
                  style: TextStyle(color: AppColors.outline, fontSize: 12),
                ),
                const SizedBox(width: 6),
                InlineNumberStepper(
                  value: p.deductAmount,
                  min: 1,
                  onChanged: onChangeAmount,
                ),
              ],
            ),
          ] else if (p.candidates.isEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              '库存中没有匹配项,这条将被跳过。',
              style: TextStyle(color: AppColors.outline, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
