import 'package:flutter/material.dart';
import '../../data/food_categories.dart';
import '../../models/proposal.dart';
import '../../models/storage_area.dart';
import '../../theme/app_theme.dart';
import '../../utils/storage_labels.dart';
import 'action_chip.dart';
import 'inline_number_stepper.dart';
import 'picker_sheet.dart';
import 'provenance_badge.dart';

class IntakeProposalRow extends StatefulWidget {
  const IntakeProposalRow({
    super.key,
    required this.proposal,
    required this.onChanged,
    required this.onToggleSelected,
    required this.onToggleAction,
  });

  final IntakeProposal proposal;
  final ValueChanged<IntakeProposal> onChanged;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleAction;

  @override
  State<IntakeProposalRow> createState() => _IntakeProposalRowState();
}

class _IntakeProposalRowState extends State<IntakeProposalRow> {
  bool _editingName = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.proposal.name);
  }

  @override
  void didUpdateWidget(covariant IntakeProposalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editingName && oldWidget.proposal.name != widget.proposal.name) {
      _nameCtrl.text = widget.proposal.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.proposal;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.selected
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: p.selected
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.hair,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onToggleSelected,
                child: Icon(
                  p.selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: p.selected ? AppColors.primary : AppColors.outline,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ProvenanceBadge(origin: p.origin, userEdited: p.userEdited),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _name(p)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: ProposalActionChip.intake(
                  intakeAction: p.action,
                  mergeTargetLabel: p.mergeTargetLabel,
                  onToggle: widget.onToggleAction,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '数量',
                    style: TextStyle(
                      color: AppColors.outline,
                      fontSize: AppFontSize.sm,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InlineNumberStepper(
                    value: p.quantity,
                    min: 1,
                    onChanged: (v) => widget.onChanged(
                      p.copyWith(quantity: v, userEdited: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _unitChip(p),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '保质期',
                    style: TextStyle(
                      color: AppColors.outline,
                      fontSize: AppFontSize.sm,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if ((p.shelfLifeDays ?? 0) <= 0)
                    // null/0 means "no expiry" (e.g. non-perishables); show an
                    // explicit unset affordance instead of a misleading "0 天",
                    // so an item can never be confirmed as expired-on-arrival.
                    GestureDetector(
                      onTap: () => widget.onChanged(
                        p.copyWith(shelfLifeDays: 7, userEdited: true),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text(
                          '未设置 · 点按设置',
                          style: TextStyle(
                            color: AppColors.outline,
                            fontSize: AppFontSize.sm,
                          ),
                        ),
                      ),
                    )
                  else
                    InlineNumberStepper(
                      value: p.shelfLifeDays!.toString(),
                      min: 1,
                      onChanged: (v) => widget.onChanged(
                        p.copyWith(
                          shelfLifeDays: int.tryParse(v) ?? 1,
                          userEdited: true,
                        ),
                      ),
                      suffix: '天',
                    ),
                ],
              ),
              _categoryChip(p),
              _storageChip(p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _name(IntakeProposal p) {
    if (!_editingName) {
      return GestureDetector(
        onTap: () => setState(() => _editingName = true),
        child: Text(
          p.name.isEmpty ? '(无名)' : p.name,
          style: const TextStyle(
            fontSize: AppFontSize.lg,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return TextField(
      controller: _nameCtrl,
      autofocus: true,
      style: const TextStyle(
        fontSize: AppFontSize.lg,
        fontWeight: FontWeight.w700,
      ),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
      ),
      onSubmitted: (v) => _commitName(v),
      onTapOutside: (_) => _commitName(_nameCtrl.text),
    );
  }

  void _commitName(String v) {
    final trimmed = v.trim();
    if (trimmed != widget.proposal.name) {
      widget.onChanged(
        widget.proposal.copyWith(name: trimmed, userEdited: true),
      );
    }
    setState(() => _editingName = false);
  }

  Widget _unitChip(IntakeProposal p) {
    return _pill(
      label: p.unit.isEmpty ? '单位' : p.unit,
      onTap: () async {
        final chosen = await PickerSheet.show<String>(
          context,
          title: '单位',
          options: const [
            PickerOption(value: '个', label: '个'),
            PickerOption(value: '只', label: '只'),
            PickerOption(value: '把', label: '把'),
            PickerOption(value: '盒', label: '盒'),
            PickerOption(value: '袋', label: '袋'),
            PickerOption(value: '瓶', label: '瓶'),
            PickerOption(value: '罐', label: '罐'),
            PickerOption(value: 'kg', label: 'kg'),
            PickerOption(value: 'g', label: 'g'),
            PickerOption(value: 'L', label: 'L'),
            PickerOption(value: 'ml', label: 'ml'),
            PickerOption(value: '份', label: '份'),
          ],
          selected: p.unit,
        );
        if (chosen != null) {
          widget.onChanged(p.copyWith(unit: chosen, userEdited: true));
        }
      },
    );
  }

  Widget _categoryChip(IntakeProposal p) {
    return _pill(
      label: '分类:${p.category ?? '其他'}',
      onTap: () async {
        final chosen = await PickerSheet.show<String>(
          context,
          title: '分类',
          options: FoodCategories.values
              .map((c) => PickerOption(value: c, label: c))
              .toList(),
          selected: p.category,
        );
        if (chosen != null) {
          widget.onChanged(p.copyWith(category: chosen, userEdited: true));
        }
      },
    );
  }

  Widget _storageChip(IntakeProposal p) {
    return _pill(
      label: '存:${storageLabelFor(p.storage)}',
      onTap: () async {
        final chosen = await PickerSheet.show<IconType>(
          context,
          title: '存储位置',
          options: IconType.values
              .map((i) => PickerOption(value: i, label: storageLabelFor(i)))
              .toList(),
          selected: p.storage,
        );
        if (chosen != null) {
          widget.onChanged(p.copyWith(storage: chosen, userEdited: true));
        }
      },
    );
  }

  Widget _pill({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}
