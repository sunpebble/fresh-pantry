import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proposal.dart';
import '../models/storage_area.dart';
import 'inventory_provider.dart';
import 'storage_service_provider.dart';

const intakeReviewDraftKey = 'intake_review_draft';

@immutable
class IntakeReviewState {
  const IntakeReviewState({this.proposals = const []});
  final List<IntakeProposal> proposals;

  IntakeReviewState copyWith({List<IntakeProposal>? proposals}) =>
      IntakeReviewState(proposals: proposals ?? this.proposals);

  int get selectedCount => proposals.where((p) => p.selected).length;
}

class IntakeReviewNotifier extends Notifier<IntakeReviewState> {
  @override
  IntakeReviewState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(intakeReviewDraftKey);
    if (raw == null) return const IntakeReviewState();
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return IntakeReviewState(
        proposals: list.map(_proposalFromJson).toList(),
      );
    } catch (_) {
      return const IntakeReviewState();
    }
  }

  void seed(List<IntakeProposal> proposals) {
    state = IntakeReviewState(proposals: proposals);
    _persistDraft();
  }

  void clear() {
    state = const IntakeReviewState();
    _persistDraft();
  }

  void toggleSelected(String id) {
    state = state.copyWith(
      proposals: state.proposals
          .map((p) => p.id == id ? p.copyWith(selected: !p.selected) : p)
          .toList(),
    );
    _persistDraft();
  }

  void toggleAction(String id) {
    state = state.copyWith(
      proposals: state.proposals.map((p) {
        if (p.id != id) return p;
        if (p.mergeTargetId == null) return p; // no merge target → can't toggle
        final next = p.action == IntakeAction.newRow
            ? IntakeAction.mergeInto
            : IntakeAction.newRow;
        return p.copyWith(action: next, userEdited: true);
      }).toList(),
    );
    _persistDraft();
  }

  void updateProposal(IntakeProposal updated) {
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.id == updated.id ? updated : p).toList(),
    );
    _persistDraft();
  }

  void toggleSelectAll() {
    final allSelected = state.proposals.every((p) => p.selected);
    state = state.copyWith(
      proposals:
          state.proposals.map((p) => p.copyWith(selected: !allSelected)).toList(),
    );
    _persistDraft();
  }

  Future<void> applyToInventory(InventoryNotifier inventory) async {
    await inventory.applyIntakeProposals(state.proposals);
    clear();
  }

  Future<void> _persistDraft() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (state.proposals.isEmpty) {
      await prefs.remove(intakeReviewDraftKey);
      return;
    }
    final encoded =
        jsonEncode(state.proposals.map(_proposalToJson).toList());
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
            (j['action'] as String?) ?? IntakeAction.newRow.name),
        mergeTargetId: j['mergeTargetId'] as String?,
        mergeTargetLabel: j['mergeTargetLabel'] as String?,
        origin: FieldOrigin.values
            .byName((j['origin'] as String?) ?? FieldOrigin.ai.name),
        userEdited: j['userEdited'] as bool? ?? false,
        selected: j['selected'] as bool? ?? true,
      );
}

final intakeReviewProvider =
    NotifierProvider<IntakeReviewNotifier, IntakeReviewState>(
        IntakeReviewNotifier.new);
