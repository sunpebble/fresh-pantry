import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/review/base_review_screen.dart';
import '../widgets/review/proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';

class IntakeReviewScreen extends ConsumerStatefulWidget {
  const IntakeReviewScreen({super.key, this.title = '审核入库'});

  final String title;

  @override
  ConsumerState<IntakeReviewScreen> createState() => _IntakeReviewScreenState();
}

class _IntakeReviewScreenState extends ConsumerState<IntakeReviewScreen> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    try {
      final n = ref.read(intakeReviewProvider.notifier);
      final inventoryN = ref.read(inventoryProvider.notifier);
      await n.applyToInventory(inventoryN);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已入库')));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('入库失败，请重试')));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intakeReviewProvider);
    final n = ref.read(intakeReviewProvider.notifier);

    return BaseReviewScreen(
      title: widget.title,
      items: state.proposals,
      emptyState: const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            '没有待审核的项目。\n回到上一屏粘贴清单或选择已购买项后再来。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.outline),
          ),
        ),
      ),
      itemBuilder:
          (_, _, p) => IntakeProposalRow(
            key: Key('intake_proposal_${p.id}'),
            proposal: p,
            onChanged: n.updateProposal,
            onToggleSelected: () => n.toggleSelected(p.id),
            onToggleAction: () => n.toggleAction(p.id),
          ),
      bottomBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.proposals.length,
        confirmLabel: _isConfirming ? '入库中…' : '入库',
        onConfirm: _isConfirming ? null : _confirm,
        onToggleSelectAll: n.toggleSelectAll,
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
