import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

class FakeRemoteSyncGateway implements RemoteSyncGateway {
  final uploaded = <SyncOperation>[];
  int pushCallCount = 0;

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    pushCallCount += 1;
    uploaded.addAll(operations);
    return operations.map((operation) => operation.id).toSet();
  }
}

/// Gateway whose [pushOperations] only completes once [release] is called, so a
/// second overlapping push can be observed while the first is in flight.
class GatedRemoteSyncGateway implements RemoteSyncGateway {
  final _gate = Completer<void>();
  final batches = <List<SyncOperation>>[];

  void release() => _gate.complete();

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    batches.add(operations);
    await _gate.future;
    return operations.map((operation) => operation.id).toSet();
  }
}

/// Acknowledges every operation except [failId], simulating a mid-batch push
/// failure that stops the run (so the failed operation and its successors stay
/// queued) without throwing.
class PartialRemoteSyncGateway implements RemoteSyncGateway {
  PartialRemoteSyncGateway(this.failId);

  final String failId;
  final attempted = <String>[];

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    final acknowledged = <String>{};
    for (final operation in operations) {
      attempted.add(operation.id);
      if (operation.id == failId) break;
      acknowledged.add(operation.id);
    }
    return acknowledged;
  }
}

SyncOperation _op(String id) {
  return SyncOperation(
    id: id,
    householdId: 'household_1',
    entityType: SyncEntityType.shoppingItem,
    entityId: 'item_$id',
    operation: SyncOperationType.toggleChecked,
    patch: const {'isChecked': true},
    clientId: 'client_1',
    createdAt: DateTime.utc(2026, 5, 27),
  );
}

void main() {
  test(
    'pushPending uploads outbox operations and removes acknowledged ones',
    () async {
      final outbox = SyncOutboxRepo(AppDatabase(NativeDatabase.memory()));
      final remote = FakeRemoteSyncGateway();
      final coordinator = SyncCoordinator(outbox: outbox, remote: remote);
      final operation = _op('op_1');

      await outbox.enqueue(operation);
      await coordinator.pushPending();

      expect(remote.uploaded, [operation]);
      expect(outbox.loadPending(), isEmpty);
    },
  );

  test('overlapping pushPending calls coalesce onto one in-flight run', () async {
    final outbox = SyncOutboxRepo(AppDatabase(NativeDatabase.memory()));
    final remote = GatedRemoteSyncGateway();
    final coordinator = SyncCoordinator(outbox: outbox, remote: remote);
    await outbox.enqueue(_op('op_1'));

    final first = coordinator.pushPending();
    final second = coordinator.pushPending();

    // Second caller joined the in-flight run instead of starting a new push.
    expect(remote.batches, hasLength(1));

    remote.release();
    await Future.wait([first, second]);

    // No trailing run was scheduled because nothing new was enqueued mid-run.
    expect(remote.batches, hasLength(1));
    expect(outbox.loadPending(), isEmpty);
  });

  test(
    'partial push leaves the failed operation and its successors queued',
    () async {
      final outbox = SyncOutboxRepo(AppDatabase(NativeDatabase.memory()));
      final remote = PartialRemoteSyncGateway('op_2');
      final coordinator = SyncCoordinator(outbox: outbox, remote: remote);
      await outbox.enqueue(_op('op_1'));
      await outbox.enqueue(_op('op_2'));
      await outbox.enqueue(_op('op_3'));

      await coordinator.pushPending();

      // op_1 acknowledged and removed; op_2 (failed) and op_3 stay queued in
      // FIFO order for the next run.
      expect(
        outbox.loadPending().map((operation) => operation.id),
        ['op_2', 'op_3'],
      );
      // op_3 was not attempted after op_2 failed (ordering preserved).
      expect(remote.attempted, ['op_1', 'op_2']);
    },
  );
}
