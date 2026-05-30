import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'helpers/fake_notification_service.dart';
import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('custom expiry picker uses a Chinese date range dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          navigationProvider.overrideWith((ref) => 2),
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

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expiry-range-picker')), findsOneWidget);
    expect(find.text('选择保质期范围'), findsOneWidget);
  });

  testWidgets(
    'custom expiry range picker keeps Chinese locale on English systems',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            navigationProvider.overrideWith((ref) => 2),
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

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      final dialogContext = tester.element(
        find.byKey(const Key('expiry-range-picker')),
      );
      expect(Localizations.localeOf(dialogContext), const Locale('zh', 'CN'));
    },
  );

  testWidgets(
    'custom expiry range picker keeps the system status bar visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            navigationProvider.overrideWith((ref) => 2),
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

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('expiry-range-picker')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnnotatedRegion<SystemUiOverlayStyle> &&
                widget.value.statusBarIconBrightness == Brightness.dark &&
                widget.value.statusBarBrightness == Brightness.light,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('custom expiry range picker omits combined range header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          navigationProvider.overrideWith((ref) => 2),
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

    await tester.ensureVisible(find.text('30天后'));
    await tester.tap(find.text('30天后'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());
    final end = today.add(const Duration(days: 30));

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(
      find.text('${_formatChineseDate(today)} - ${_formatChineseDate(end)}'),
      findsNothing,
    );
    expect(find.text(_formatChineseDate(today)), findsOneWidget);
    expect(find.text(_formatChineseDate(end)), findsOneWidget);
  });

  testWidgets('custom expiry range picker uses wheel date selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          navigationProvider.overrideWith((ref) => 2),
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

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expiry-start-date-tab')), findsOneWidget);
    expect(find.byKey(const Key('expiry-end-date-tab')), findsOneWidget);
    expect(find.byKey(const Key('expiry-date-wheel')), findsOneWidget);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.minimumDate, isNull);
    expect(picker.maximumDate, isNull);
    expect(picker.minimumYear, lessThanOrEqualTo(DateTime.now().year));
    expect(picker.maximumYear, greaterThanOrEqualTo(DateTime.now().year));
    expect(find.byKey(const Key('expiry-year-selector')), findsNothing);
    expect(find.byKey(const Key('expiry-month-selector')), findsNothing);
  });

  testWidgets(
    'custom expiry wheel expands range instead of snapping to bounds',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
            systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            notificationServiceProvider.overrideWithValue(
              FakeNotificationService(),
            ),
            navigationProvider.overrideWith((ref) => 2),
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

      await tester.ensureVisible(find.text('30天后'));
      await tester.tap(find.text('30天后'));
      await tester.pumpAndSettle();

      final today = DateUtils.dateOnly(DateTime.now());
      final laterThanEnd = today.add(const Duration(days: 45));

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(laterThanEnd);
      await tester.pumpAndSettle();

      expect(
        find.text(
          '${_formatChineseDate(laterThanEnd)} - '
          '${_formatChineseDate(laterThanEnd)}',
        ),
        findsNothing,
      );
      expect(find.text(_formatChineseDate(laterThanEnd)), findsNWidgets(2));
    },
  );

  testWidgets('expiration quick presets are labeled as days from now', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          navigationProvider.overrideWith((ref) => 2),
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

    expect(find.text('3天后'), findsOneWidget);
    expect(find.text('7天后'), findsOneWidget);
    expect(find.text('14天后'), findsOneWidget);
    expect(find.text('30天后'), findsOneWidget);
  });

  testWidgets('custom expiry range picker starts on selected preset range', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          notificationServiceProvider.overrideWithValue(
            FakeNotificationService(),
          ),
          navigationProvider.overrideWith((ref) => 2),
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

    await tester.ensureVisible(find.text('30天后'));
    await tester.tap(find.text('30天后'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${_formatChineseDate(today)} - '
        '${_formatChineseDate(today.add(const Duration(days: 30)))}',
      ),
      findsNothing,
    );
    expect(find.text(_formatChineseDate(today)), findsOneWidget);
    expect(
      find.text(_formatChineseDate(today.add(const Duration(days: 30)))),
      findsOneWidget,
    );
  });
}

String _formatChineseDate(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}
