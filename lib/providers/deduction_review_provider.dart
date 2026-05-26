import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proposal.dart';
import 'inventory_provider.dart';
import 'review_notifier_base.dart';

@immutable
class DeductionReviewState {
  const DeductionReviewState({this.proposals = const []});
  final List<DeductionProposal> proposals;
  int get selectedCount =>
      proposals
          .where((p) => p.selected && p.action == DeductionAction.deduct)
          .length;
}

class DeductionReviewNotifier extends Notifier<DeductionReviewState>
    with ReviewNotifierBase<DeductionReviewState> {
  @override
  DeductionReviewState build() => const DeductionReviewState();

  void seed(List<DeductionProposal> proposals) =>
      state = DeductionReviewState(proposals: proposals);

  @override
  void clear() => state = const DeductionReviewState();

  void toggleSelected(String id) {
    state = DeductionReviewState(
      proposals:
          state.proposals
              .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
              .toList(),
    );
  }

  void toggleAction(String id) {
    state = DeductionReviewState(
      proposals:
          state.proposals.map((p) {
            if (p.id != id) return p;
            final next =
                p.action == DeductionAction.deduct
                    ? DeductionAction.skip
                    : DeductionAction.deduct;
            return p.copyWith(action: next);
          }).toList(),
    );
  }

  void chooseCandidate(String id, int candidateRowIndex) {
    state = DeductionReviewState(
      proposals:
          state.proposals
              .map(
                (p) =>
                    p.id == id ? p.copyWith(chosenIndex: candidateRowIndex) : p,
              )
              .toList(),
    );
  }

  void updateDeductAmount(String id, String amount) {
    state = DeductionReviewState(
      proposals:
          state.proposals
              .map((p) => p.id == id ? p.copyWith(deductAmount: amount) : p)
              .toList(),
    );
  }

  Future<void> applyToInventory(InventoryNotifier inventory) async {
    await applyAndClear(
      () => inventory.applyDeductionProposals(state.proposals),
    );
  }
}

final deductionReviewProvider =
    NotifierProvider<DeductionReviewNotifier, DeductionReviewState>(
      DeductionReviewNotifier.new,
    );
