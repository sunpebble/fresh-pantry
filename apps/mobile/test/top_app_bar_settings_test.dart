import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

void main() {
  testWidgets('settings icon pushes SettingsScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
      ],
      child: const MaterialApp(home: Scaffold(body: TopAppBar())),
    ));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
