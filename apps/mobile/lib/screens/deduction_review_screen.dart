import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/deduction_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_spacing.dart';
import '../widgets/review/base_review_screen.dart';
import '../widgets/review/deduction_proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';
import '../widgets/shared/fk_entrance.dart';

class DeductionReviewScreen extends ConsumerStatefulWidget {
  const DeductionReviewScreen({super.key, this.title = '审核扣库存'});

  final String title;

  @override
  ConsumerState<DeductionReviewScreen> createState() =>
      _DeductionReviewScreenState();
}

class _DeductionReviewScreenState extends ConsumerState<DeductionReviewScreen> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      final n = ref.read(deductionReviewProvider.notifier);
      final inv = ref.read(inventoryProvider.notifier);
      await n.applyToInventory(inv);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已扣减库存')));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('扣减失败，请重试')));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deductionReviewProvider);
    final n = ref.read(deductionReviewProvider.notifier);

    return BaseReviewScreen(
      title: widget.title,
      items: state.proposals,
      showBottomBarWhenEmpty: true,
      emptyState: const FkEntrance(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Text('这道菜的食材没有可扣减的库存项。', textAlign: TextAlign.center),
          ),
        ),
      ),
      itemBuilder: (_, index, p) => FkEntrance(
        index: index,
        child: DeductionProposalRow(
          key: Key('deduction_proposal_${p.id}'),
          proposal: p,
          onToggleSelected: () => n.toggleSelected(p.id),
          onToggleAction: () => n.toggleAction(p.id),
          onChooseCandidate: (idx) => n.chooseCandidate(p.id, idx),
          onChangeAmount: (v) => n.updateDeductAmount(p.id, v),
        ),
      ),
      bottomBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.deductibleCount,
        confirmLabel: _isConfirming ? '扣减中…' : '确认扣减',
        onConfirm: _isConfirming ? null : _confirm,
        onToggleSelectAll: n.toggleSelectAll,
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
