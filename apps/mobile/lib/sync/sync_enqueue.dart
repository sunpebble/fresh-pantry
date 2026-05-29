import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/storage_service_provider.dart';
import 'sync_ids.dart';
import 'sync_operation.dart';
import 'sync_providers.dart';

const _operationIds = Uuid();

/// One mutation's worth of sync intent, accumulated by callers that change
/// several rows at once (e.g. applying an Intake Review) before flushing them
/// through [SyncEnqueue.enqueueSyncBatch].
class SyncEnqueueOp {
  const SyncEnqueueOp({
    required this.entityId,
    required this.operation,
    required this.patch,
    this.baseVersion,
  });

  final String entityId;
  final SyncOperationType operation;
  final Map<String, dynamic> patch;
  final int? baseVersion;
}

/// Concentrates the sync-facing half of every notifier mutation: minting a sync
/// id and recording a sync operation in the outbox, then kicking a push.
///
/// Each stateful notifier mixes this in and declares its [syncEntityType]; the
/// household guard, id minting, [SyncOperation] construction and push trigger
/// live here once instead of being copied across `InventoryNotifier`,
/// `ShoppingNotifier`, and `CustomRecipeNotifier`.
mixin SyncEnqueue<StateT> on Notifier<StateT> {
  /// Which entity kind this notifier's mutations belong to.
  SyncEntityType get syncEntityType;

  /// The household this notifier currently syncs to, or empty when the app is
  /// running local-only (no household selected).
  String get _householdId => ref.read(selectedHouseholdIdProvider).trim();

  /// The id an entity should persist under: a fresh sync UUID when the notifier
  /// is attached to a household and [currentId] isn't already one, else
  /// [currentId] unchanged (local-only rows keep their local id until joined).
  String syncIdFor(String currentId) {
    if (_householdId.isEmpty || isUuid(currentId)) return currentId;
    return newSyncEntityId();
  }

  /// Records one mutation in the sync outbox and kicks a push.
  ///
  /// No-ops when the app is local-only (no household) or [entityId] is blank:
  /// there is no household to sync to, so skipping is the correct local-first
  /// behaviour — not a dropped write.
  Future<void> enqueueSync({
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> patch,
    int? baseVersion,
  }) {
    final householdId = _householdId;
    if (householdId.isEmpty || entityId.trim().isEmpty) {
      return Future.value();
    }

    return ref
        .read(syncOutboxRepoProvider)
        .enqueue(
          SyncOperation(
            id: _operationIds.v4(),
            householdId: householdId,
            entityType: syncEntityType,
            entityId: entityId,
            operation: operation,
            patch: patch,
            baseVersion: baseVersion,
            clientId: ref.read(syncClientIdProvider),
            createdAt: DateTime.now().toUtc(),
          ),
        )
        .then((_) => unawaited(ref.read(syncPushPendingProvider)()));
  }

  /// Enqueues a batch of mutations in order — e.g. an Intake Review that creates
  /// some rows and merges into others in one apply.
  Future<void> enqueueSyncBatch(Iterable<SyncEnqueueOp> operations) async {
    for (final op in operations) {
      await enqueueSync(
        entityId: op.entityId,
        operation: op.operation,
        patch: op.patch,
        baseVersion: op.baseVersion,
      );
    }
  }
}
