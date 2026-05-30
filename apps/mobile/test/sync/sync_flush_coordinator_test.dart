import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/providers/connectivity_provider.dart';
import 'package:fresh_pantry/sync/sync_flush_coordinator.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

void main() {
  testWidgets('regaining connectivity triggers a flush', (tester) async {
    final online = StreamController<bool>.broadcast();
    var flushes = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectivityOnlineProvider.overrideWith((ref) => online.stream),
        syncPushPendingProvider.overrideWithValue(() async => flushes++),
      ],
      child: const MaterialApp(
        home: SyncFlushCoordinator(child: SizedBox.shrink()),
      ),
    ));
    online.add(false);
    await tester.pump();
    online.add(true); // offline -> online
    await tester.pump();
    expect(flushes, greaterThanOrEqualTo(1));
    await online.close();
  });
}
