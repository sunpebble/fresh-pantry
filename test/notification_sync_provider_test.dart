import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/scheduled_notification.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/notification_sync_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('does not sync when notification permission is denied', () async {
    final container = await _container(
      service: _RecordingNotificationService(permission: false),
      inventory: [_ingredient('牛奶')],
    );
    addTearDown(container.dispose);

    expect(container.read(notificationSyncProvider), isEmpty);
    await _flushMicrotasks();

    final service =
        container.read(notificationServiceProvider)
            as _RecordingNotificationService;
    expect(service.syncCalls, 0);
    expect(container.read(notificationSyncProvider), isEmpty);
  });

  test(
    'uses provider state as previous notification IDs across rebuilds',
    () async {
      final service = _RecordingNotificationService(permission: true);
      final container = await _container(
        service: service,
        inventory: [_ingredient('牛奶')],
      );
      addTearDown(container.dispose);

      container.read(notificationSyncProvider);
      await _flushMicrotasks();
      final firstIds = container.read(notificationSyncProvider);
      expect(firstIds, isNotEmpty);
      expect(service.previousIdsLog.single, isEmpty);

      await container
          .read(inventoryProvider.notifier)
          .add(_ingredient('鸡蛋', addedAt: DateTime(2026, 5, 2)));
      container.read(notificationSyncProvider);
      await _flushMicrotasks();

      expect(service.syncCalls, 2);
      expect(service.previousIdsLog.last, firstIds);
      expect(container.read(notificationSyncProvider), isNot(firstIds));
    },
  );

  test('reports scheduler errors and leaves state unchanged', () async {
    final errors = _captureFlutterErrors();
    final service = _RecordingNotificationService(permission: true);
    final container = await _container(
      service: service,
      inventory: [_ingredient('牛奶')],
      overrides: [
        expiryScheduleComputerProvider.overrideWithValue(({
          required inventory,
          required settings,
          required now,
        }) {
          throw StateError('compute failed');
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(notificationSyncProvider), isEmpty);
    await _flushMicrotasks();

    expect(service.syncCalls, 0);
    expect(container.read(notificationSyncProvider), isEmpty);
    expect(errors.single.exception, isA<StateError>());
  });

  test('reports syncAll errors and keeps previous notification IDs', () async {
    final errors = _captureFlutterErrors();
    final service = _RecordingNotificationService(
      permission: true,
      throwOnSync: true,
    );
    final container = await _container(
      service: service,
      inventory: [_ingredient('牛奶')],
    );
    addTearDown(container.dispose);

    expect(container.read(notificationSyncProvider), isEmpty);
    await _flushMicrotasks();

    expect(service.syncCalls, 1);
    expect(container.read(notificationSyncProvider), isEmpty);
    expect(errors.single.exception, isA<StateError>());
  });
}

Future<ProviderContainer> _container({
  required _RecordingNotificationService service,
  required List<Ingredient> inventory,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      inventorySeedProvider.overrideWithValue(inventory),
      notificationServiceProvider.overrideWithValue(service),
      ...overrides,
    ],
  );
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

List<FlutterErrorDetails> _captureFlutterErrors() {
  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previousOnError);
  return errors;
}

Ingredient _ingredient(String name, {DateTime? addedAt}) {
  final createdAt = addedAt ?? DateTime(2026, 5, 1);
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '个',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: FoodCategories.dairyAndEggs,
    storage: IconType.fridge,
    addedAt: createdAt,
    expiryDate: DateTime.now().add(const Duration(days: 5)),
  );
}

class _RecordingNotificationService extends NotificationService {
  _RecordingNotificationService({
    required this.permission,
    this.throwOnSync = false,
  }) : super();

  final bool permission;
  final bool throwOnSync;
  int syncCalls = 0;
  final previousIdsLog = <List<int>>[];

  @override
  bool get isInitialized => true;

  @override
  bool get permissionGranted => permission;

  @override
  Future<void> init({void Function(int notificationId)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> syncAll(
    List<ScheduledNotification> next, {
    required List<int> previousIds,
  }) async {
    syncCalls++;
    previousIdsLog.add(List<int>.from(previousIds));
    if (throwOnSync) {
      throw StateError('sync failed');
    }
  }
}
