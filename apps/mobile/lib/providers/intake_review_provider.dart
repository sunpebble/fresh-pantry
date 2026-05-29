import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient_identity.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'inventory_provider.dart';
import 'review_notifier_base.dart';
import 'storage_service_provider.dart';

const intakeReviewDraftKey = 'intake_review_draft';

@immutable
class IntakeReviewState {
  const IntakeReviewState({this.proposals = const [], this.persistError});

  final List<IntakeProposal> proposals;
  final Object? persistError;

  IntakeReviewState copyWith({
    List<IntakeProposal>? proposals,
    Object? persistError,
    bool clearPersistError = false,
  }) => IntakeReviewState(
    proposals: proposals ?? this.proposals,
    persistError: clearPersistError ? null : persistError ?? this.persistError,
  );

  int get selectedCount => proposals.where((p) => p.selected).length;
}

class IntakeReviewNotifier extends Notifier<IntakeReviewState>
    with ReviewNotifierBase<IntakeReviewState> {
  @override
  IntakeReviewState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(intakeReviewDraftKey);
    if (raw == null) return const IntakeReviewState();
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return IntakeReviewState(proposals: list.map(_proposalFromJson).toList());
    } catch (_) {
      return const IntakeReviewState();
    }
  }

  void seed(List<IntakeProposal> proposals) {
    state = IntakeReviewState(proposals: proposals);
    _schedulePersistDraft();
  }

  @override
  void clear() {
    state = const IntakeReviewState();
    _schedulePersistDraft();
  }

  void toggleSelected(String id) {
    state = state.copyWith(
      proposals:
          state.proposals
              .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
              .toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  void toggleAction(String id) {
    state = state.copyWith(
      proposals:
          state.proposals.map((p) {
            if (p.id != id) return p;
            if (p.mergeTargetId == null) {
              return p; // no merge target -> can't toggle
            }
            // Perishables always create a new Batch; never let the user toggle
            // one into a merge.
            if (p.action == IntakeAction.newRow &&
                IngredientIdentity.isPerishable(
                  category: p.category,
                  name: p.name,
                )) {
              return p;
            }
            final next =
                p.action == IntakeAction.newRow
                    ? IntakeAction.mergeInto
                    : IntakeAction.newRow;
            return p.copyWith(action: next, userEdited: true);
          }).toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  void updateProposal(IntakeProposal updated) {
    final coerced = _coerceActionForRules(updated);
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.id == coerced.id ? coerced : p).toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  /// Keeps the Review action consistent with the domain rule after an edit:
  /// if a change makes the proposal Perishable, drop any stale `mergeInto` so
  /// the UI reflects that perishables always create a new Batch.
  IntakeProposal _coerceActionForRules(IntakeProposal p) {
    if (p.action == IntakeAction.mergeInto &&
        IngredientIdentity.isPerishable(category: p.category, name: p.name)) {
      return p.copyWith(action: IntakeAction.newRow);
    }
    return p;
  }

  void toggleSelectAll() {
    final allSelected = state.proposals.every((p) => p.selected);
    state = state.copyWith(
      proposals:
          state.proposals
              .map((p) => p.copyWith(selected: !allSelected))
              .toList(),
      clearPersistError: true,
    );
    _schedulePersistDraft();
  }

  /// Applies the reviewed proposals and returns the ids of the proposals that
  /// were actually applied, so the caller can clean up only those source rows.
  Future<Set<String>> applyToInventory(InventoryNotifier inventory) async {
    return applyAndClear(() => inventory.applyIntakeProposals(state.proposals));
  }

  void _schedulePersistDraft() {
    unawaited(
      _persistDraft()
          .then((_) {
            if (state.persistError != null) {
              state = state.copyWith(clearPersistError: true);
            }
          })
          .catchError((Object error) {
            state = state.copyWith(persistError: error);
          }),
    );
  }

  Future<void> _persistDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (state.proposals.isEmpty) {
      await prefs.remove(intakeReviewDraftKey);
      return;
    }
    final encoded = jsonEncode(state.proposals.map(_proposalToJson).toList());
    await prefs.setString(intakeReviewDraftKey, encoded);
  }

  Map<String, dynamic> _proposalToJson(IntakeProposal p) => {
    'id': p.id,
    'name': p.name,
    'quantity': p.quantity,
    'unit': p.unit,
    'category': p.category,
    'storage': p.storage.name,
    'shelfLifeDays': p.shelfLifeDays,
    'action': p.action.name,
    'mergeTargetId': p.mergeTargetId,
    'mergeTargetLabel': p.mergeTargetLabel,
    'origin': p.origin.name,
    'userEdited': p.userEdited,
    'selected': p.selected,
  };

  IntakeProposal _proposalFromJson(Map<String, dynamic> j) => IntakeProposal(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    quantity: j['quantity'] as String? ?? '1',
    unit: j['unit'] as String? ?? '个',
    category: j['category'] as String?,
    storage: iconTypeFromName(j['storage'] as String?),
    shelfLifeDays: (j['shelfLifeDays'] as num?)?.toInt(),
    action: IntakeAction.values.byName(
      (j['action'] as String?) ?? IntakeAction.newRow.name,
    ),
    mergeTargetId: j['mergeTargetId'] as String?,
    mergeTargetLabel: j['mergeTargetLabel'] as String?,
    origin: FieldOrigin.values.byName(
      (j['origin'] as String?) ?? FieldOrigin.ai.name,
    ),
    userEdited: j['userEdited'] as bool? ?? false,
    selected: j['selected'] as bool? ?? true,
  );
}

final intakeReviewProvider =
    NotifierProvider<IntakeReviewNotifier, IntakeReviewState>(
      IntakeReviewNotifier.new,
    );
