import 'package:drift/drift.dart';

import '../storage/drift/app_database.dart';
import '../storage/drift/entity_row_codec.dart';
import 'sync_operation.dart';

class SyncOutboxRepo {
  SyncOutboxRepo(this._db);

  final AppDatabase _db;
  List<SyncOperation> _cache = const [];

  /// 预读 outbox 到内存(main.dart / 测试 setUp 调用)。
  Future<void> hydratePending() async {
    _cache = await _readAll();
  }

  /// 同步读取(供 enqueueSync / household_content_sync 的同步路径)。
  List<SyncOperation> loadPending() => _cache;

  Future<void> enqueue(SyncOperation operation) async {
    await _db.into(_db.syncOutbox).insertOnConflictUpdate(
          outboxCompanionFor(operation),
        );
    _cache = await _readAll();
  }

  Future<void> removeAcknowledged(Set<String> operationIds) async {
    if (operationIds.isEmpty) return;
    await (_db.delete(_db.syncOutbox)
          ..where((t) => t.id.isIn(operationIds)))
        .go();
    _cache = await _readAll();
  }

  Future<void> replaceAll(List<SyncOperation> operations) async {
    await _db.transaction(() async {
      await _db.delete(_db.syncOutbox).go();
      await _db.batch((b) {
        b.insertAll(_db.syncOutbox, operations.map(outboxCompanionFor));
      });
    });
    _cache = await _readAll();
  }

  Future<List<SyncOperation>> _readAll() async {
    final rows = await (_db.select(_db.syncOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    final ops = <SyncOperation>[];
    for (final row in rows) {
      try {
        ops.add(outboxFromRow(row));
      } catch (_) {
        // skip malformed op
      }
    }
    return ops;
  }
}
