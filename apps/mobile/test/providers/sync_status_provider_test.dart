import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/connectivity_provider.dart';
import 'package:fresh_pantry/providers/sync_status_provider.dart';

ProviderContainer _container({required bool online, required int pending}) {
  final c = ProviderContainer(overrides: [
    connectivityOnlineProvider.overrideWith((ref) => Stream.value(online)),
    pendingSyncCountProvider.overrideWith((ref) => Stream.value(pending)),
  ]);
  // Keep the stream providers subscribed so their values are available.
  c.listen(connectivityOnlineProvider, (previous, next) {});
  c.listen(pendingSyncCountProvider, (previous, next) {});
  return c;
}

void main() {
  test('offline with pending shows offline banner', () async {
    final c = _container(online: false, pending: 3);
    addTearDown(c.dispose);

    await c.read(connectivityOnlineProvider.future);
    await c.read(pendingSyncCountProvider.future);

    final status = c.read(syncStatusProvider);
    expect(status.online, isFalse);
    expect(status.pendingCount, 3);
    expect(status.showBanner, isTrue);
  });

  test('online with empty outbox hides banner', () async {
    final c = _container(online: true, pending: 0);
    addTearDown(c.dispose);

    await c.read(connectivityOnlineProvider.future);
    await c.read(pendingSyncCountProvider.future);

    final status = c.read(syncStatusProvider);
    expect(status.online, isTrue);
    expect(status.pendingCount, 0);
    expect(status.showBanner, isFalse);
  });

  test('online with pending shows syncing banner', () async {
    final c = _container(online: true, pending: 2);
    addTearDown(c.dispose);

    await c.read(connectivityOnlineProvider.future);
    await c.read(pendingSyncCountProvider.future);

    final status = c.read(syncStatusProvider);
    expect(status.online, isTrue);
    expect(status.pendingCount, 2);
    expect(status.showBanner, isTrue);
  });

  test('defaults to online with no pending before streams emit', () {
    // Both stream providers overridden with never-emitting streams: the derived
    // provider falls back to online=true + pending=0 (no banner).
    final c = ProviderContainer(overrides: [
      connectivityOnlineProvider.overrideWith((ref) => const Stream.empty()),
      pendingSyncCountProvider.overrideWith((ref) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);

    final status = c.read(syncStatusProvider);
    expect(status.online, isTrue);
    expect(status.pendingCount, 0);
    expect(status.showBanner, isFalse);
  });
}
