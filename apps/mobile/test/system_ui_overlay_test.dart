import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'helpers/fake_notification_service.dart';
import 'helpers/household_gateway_stub.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('uses dark system chrome on light app surfaces', (tester) async {
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

    // Find the AnnotatedRegion that wraps FreshPantryApp's MaterialApp.
    // Locating it through the FreshPantryApp ancestor avoids depending on
    // the (non-deterministic) order of nested AnnotatedRegions used by the
    // framework internally.
    final appShellRegion = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(FreshPantryApp),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is AnnotatedRegion<SystemUiOverlayStyle> &&
                  widget.value.systemNavigationBarColor == AppColors.surface,
            ),
          )
          .first,
    );

    expect(appShellRegion.value.statusBarIconBrightness, Brightness.dark);
    expect(appShellRegion.value.statusBarBrightness, Brightness.light);
    expect(
      appShellRegion.value.systemNavigationBarIconBrightness,
      Brightness.dark,
    );
    expect(appShellRegion.value.systemNavigationBarColor, AppColors.surface);
  });
}
