import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

SyncOperation _op(String id) => SyncOperation(
      id: id, householdId: 'h1', entityType: SyncEntityType.inventoryItem,
      entityId: 'a', operation: SyncOperationType.create, patch: const {},
      clientId: 'c', createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late AppDatabase db;
  late SyncOutboxRepo repo;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = SyncOutboxRepo(db);
    await repo.hydratePending();
  });
  tearDown(() => db.close());

  test('enqueue persists and loadPending (sync) reflects it', () async {
    await repo.enqueue(_op('op1'));
    expect(repo.loadPending().map((o) => o.id), ['op1']);
  });

  test('removeAcknowledged drops only acked', () async {
    await repo.enqueue(_op('op1'));
    await repo.enqueue(_op('op2'));
    await repo.removeAcknowledged({'op1'});
    expect(repo.loadPending().map((o) => o.id), ['op2']);
  });

  test('survives a fresh repo over same db (true persistence)', () async {
    await repo.enqueue(_op('op1'));
    final repo2 = SyncOutboxRepo(db);
    await repo2.hydratePending();
    expect(repo2.loadPending().map((o) => o.id), ['op1']);
  });
}
