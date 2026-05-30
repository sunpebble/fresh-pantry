import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/storage/shared_prefs_storage_adapter.dart';
import 'helpers/fake_notification_service.dart';
import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';
import 'package:fresh_pantry/widgets/shared/fk_hero_header.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders Fresh Pantry app shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = SharedPrefsStorageAdapter(prefs);
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          storageAdapterProvider.overrideWithValue(adapter),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Bottom navigation chrome must be present on the home shell.
    expect(find.byType(BottomNavBar), findsOneWidget);
    // FK redesign hero: total inventory stat label appears.
    expect(find.text('你的冰箱状态'), findsOneWidget);
    // 5-tab nav shows the four labelled tabs (middle is a label-less FAB).
    for (final label in const ['首页', '食材', '菜谱', '清单']) {
      expect(find.text(label), findsOneWidget);
    }

    // 首页 Header 是 hero 的一部分(被 FkHeroHeader 渐变包裹),随列表一起滚动 —
    // 既让蓝色无缝铺到顶,又避免固定浮层在滚动时重叠或遮挡下方内容。
    expect(
      find.ancestor(
        of: find.byType(TopAppBar),
        matching: find.byType(FkHeroHeader),
      ),
      findsOneWidget,
    );
  });

  testWidgets('handles Supabase auth callback route with query parameters', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = SharedPrefsStorageAdapter(prefs);
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          storageAdapterProvider.overrideWithValue(adapter),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('pushRouteInformation', {
        'location': '/?code=8e323390-9fc8-4a1c-a692-2909516b323b',
        'state': null,
      }),
    );
    final result = await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/navigation', message, (_) {});

    expect(const JSONMethodCodec().decodeEnvelope(result!), isTrue);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomNavBar), findsOneWidget);
  });

  testWidgets('AppShell cancels share stream subscription on dispose', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = SharedPrefsStorageAdapter(prefs);
    final shareSource = _CancellableShareSource();
    addTearDown(shareSource.close);
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          storageAdapterProvider.overrideWithValue(adapter),
          systemShareSourceProvider.overrideWithValue(shareSource),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          householdSessionControllerProvider.overrideWith(
            (ref) => HouseholdSessionController(
              HouseholdGatewayStub(isAuthenticated: true),
            ),
          ),
        ],
        child: const FreshPantryApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(shareSource.canceled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(shareSource.canceled, isTrue);
  });
}

class _CancellableShareSource implements SystemShareSource {
  bool canceled = false;

  late final StreamController<String> _controller =
      StreamController<String>.broadcast(onCancel: () => canceled = true);

  @override
  Stream<String> get incomingTextStream => _controller.stream;

  @override
  Future<String?> consumeInitialText() async => null;

  Future<void> close() => _controller.close();
}
