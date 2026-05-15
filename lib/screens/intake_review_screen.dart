import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/intake_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/review/proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';

class IntakeReviewScreen extends ConsumerWidget {
  const IntakeReviewScreen({super.key, this.title = '审核入库'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(intakeReviewProvider);
    final n = ref.read(intakeReviewProvider.notifier);
    final inventoryN = ref.read(inventoryProvider.notifier);

    if (state.proposals.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '没有待审核的项目。\n回到上一屏粘贴清单或选择已购买项后再来。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.outline),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: state.proposals.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = state.proposals[i];
          return IntakeProposalRow(
            key: Key('intake_proposal_${p.id}'),
            proposal: p,
            onChanged: n.updateProposal,
            onToggleSelected: () => n.toggleSelected(p.id),
            onToggleAction: () => n.toggleAction(p.id),
          );
        },
      ),
      bottomNavigationBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.proposals.length,
        confirmLabel: '入库',
        onConfirm: () async {
          await n.applyToInventory(inventoryN);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已入库')),
          );
          Navigator.of(context).maybePop();
        },
        onToggleSelectAll: n.toggleSelectAll,
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
