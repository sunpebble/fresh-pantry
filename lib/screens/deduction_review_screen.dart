import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/deduction_review_provider.dart';
import '../providers/inventory_provider.dart';
import '../widgets/review/deduction_proposal_row.dart';
import '../widgets/review/review_bottom_bar.dart';

class DeductionReviewScreen extends ConsumerWidget {
  const DeductionReviewScreen({super.key, this.title = '审核扣库存'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deductionReviewProvider);
    final n = ref.read(deductionReviewProvider.notifier);
    final inv = ref.read(inventoryProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: state.proposals.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这道菜的食材没有可扣减的库存项。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: state.proposals.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = state.proposals[i];
                return DeductionProposalRow(
                  key: Key('deduction_proposal_${p.id}'),
                  proposal: p,
                  onToggleSelected: () => n.toggleSelected(p.id),
                  onToggleAction: () => n.toggleAction(p.id),
                  onChooseCandidate: (idx) => n.chooseCandidate(p.id, idx),
                  onChangeAmount: (v) => n.updateDeductAmount(p.id, v),
                );
              },
            ),
      bottomNavigationBar: ReviewBottomBar(
        selectedCount: state.selectedCount,
        totalCount: state.proposals.length,
        confirmLabel: '确认扣减',
        onConfirm: () async {
          await n.applyToInventory(inv);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已扣减库存')),
          );
          Navigator.of(context).maybePop();
        },
        onToggleSelectAll: () {
          // No-op for deduction; selection per row only.
        },
        onCancel: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
