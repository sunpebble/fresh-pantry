import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/background_sync.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

import '../support/test_database.dart';

/// Records how many times the headless drain pushed, standing in for the real
/// Supabase gateway (which needs platform channels we can't reach in a unit
/// test). The dispatcher/`runBackgroundSyncPush` wiring is verified by analyze +
/// build; this test pins the pure, isolate-safe core: [drainOutbox].
class _RecordingGateway implements RemoteSyncGateway {
  int calls = 0;

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    calls++;
    return operations.map((operation) => operation.id).toSet();
  }
}

SyncOperation _op(String id) => SyncOperation(
  id: id,
  householdId: 'h1',
  entityType: SyncEntityType.inventoryItem,
  entityId: 'a',
  operation: SyncOperationType.create,
  patch: const {},
  clientId: 'c',
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  test('drainOutbox pushes pending operations and clears the outbox', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    await outbox.hydratePending();
    await outbox.enqueue(_op('op1'));
    final gateway = _RecordingGateway();

    await drainOutbox(outbox: outbox, remote: gateway);

    expect(gateway.calls, 1);
    expect(outbox.loadPending(), isEmpty);
  });

  test('drainOutbox leaves the gateway untouched when nothing is pending', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    await outbox.hydratePending();
    final gateway = _RecordingGateway();

    await drainOutbox(outbox: outbox, remote: gateway);

    expect(gateway.calls, 0);
  });
}
