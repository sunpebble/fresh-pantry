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
      proposals.where((p) => p.selected && _isDeductibleProposal(p)).length;
  int get deductibleCount => proposals.where(_isDeductibleProposal).length;
}

bool _hasChosenCandidate(DeductionProposal proposal) {
  return proposal.candidates.any(
    (candidate) => candidate.inventoryRowIndex == proposal.chosenIndex,
  );
}

bool _isDeductibleProposal(DeductionProposal proposal) {
  return proposal.action == DeductionAction.deduct &&
      _hasChosenCandidate(proposal);
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
          state.proposals.map((p) {
            if (p.id != id) return p;
            if (!_isDeductibleProposal(p)) {
              return p.copyWith(selected: false);
            }
            return p.copyWith(selected: !p.selected);
          }).toList(),
    );
  }

  void toggleAction(String id) {
    state = DeductionReviewState(
      proposals:
          state.proposals.map((p) {
            if (p.id != id) return p;
            if (p.action == DeductionAction.deduct) {
              return p.copyWith(action: DeductionAction.skip, selected: false);
            }
            if (!_hasChosenCandidate(p)) {
              return p.copyWith(action: DeductionAction.skip, selected: false);
            }
            return p.copyWith(action: DeductionAction.deduct, selected: true);
          }).toList(),
    );
  }

  void chooseCandidate(String id, int candidateRowIndex) {
    state = DeductionReviewState(
      proposals:
          state.proposals.map((p) {
            if (p.id != id) return p;
            final isKnownCandidate = p.candidates.any(
              (candidate) => candidate.inventoryRowIndex == candidateRowIndex,
            );
            if (!isKnownCandidate) return p;
            return p.copyWith(
              chosenIndex: candidateRowIndex,
              action: DeductionAction.deduct,
              selected: true,
            );
          }).toList(),
    );
  }

  void updateDeductAmount(String id, String amount) {
    final trimmedAmount = amount.trim();
    final parsed = double.tryParse(trimmedAmount);
    final normalizedAmount =
        parsed != null && parsed <= 0 ? '1' : trimmedAmount;
    state = DeductionReviewState(
      proposals:
          state.proposals
              .map(
                (p) =>
                    p.id == id ? p.copyWith(deductAmount: normalizedAmount) : p,
              )
              .toList(),
    );
  }

  void toggleSelectAll() {
    final deductible = state.proposals.where(_isDeductibleProposal).toList();
    final allSelected =
        deductible.isNotEmpty && deductible.every((p) => p.selected);
    state = DeductionReviewState(
      proposals:
          state.proposals.map((p) {
            if (!_isDeductibleProposal(p)) {
              return p.copyWith(selected: false);
            }
            return p.copyWith(selected: !allSelected);
          }).toList(),
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
