import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:fresh_pantry/widgets/settings/household_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/household_gateway_stub.dart';

void main() {
  testWidgets('invite button opens email input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            onInviteEmail: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('邀请成员'));
    await tester.pumpAndSettle();

    expect(find.text('成员邮箱'), findsOneWidget);
  });

  testWidgets('invite dialog submits the entered email', (tester) async {
    var submittedEmail = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            onInviteEmail: (email) async {
              submittedEmail = email;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('邀请成员'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '成员邮箱'),
      ' family@example.com ',
    );
    await tester.tap(find.text('发送邀请'));
    await tester.pumpAndSettle();

    expect(submittedEmail, ' family@example.com ');
    expect(find.text('成员邮箱'), findsNothing);
  });

  testWidgets(
    'SettingsScreen renders household members after household loads',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gateway = HouseholdGatewayStub(
        households: const [
          Household(
            id: 'household_1',
            name: 'Kunish Kitchen',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
        ],
        members: const [
          HouseholdMember(
            householdId: 'household_1',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
          HouseholdMember(
            householdId: 'household_1',
            userId: 'member_1',
            role: 'member',
            email: 'member@example.com',
          ),
        ],
        isAuthenticated: true,
        emitInitialAuthState: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationServiceProvider.overrideWithValue(
              NotificationService(),
            ),
            householdGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kunish Kitchen'), findsNWidgets(2));
      expect(find.text('owner@example.com'), findsNWidgets(2));
      expect(find.text('member@example.com'), findsOneWidget);
      expect(find.text('登录后会显示家庭成员'), findsNothing);
    },
  );

  testWidgets(
    'SettingsScreen creates invite for current household and copies link',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gateway = HouseholdGatewayStub(
        households: const [
          Household(
            id: 'household_1',
            name: 'Kunish Kitchen',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
        ],
        emitInitialAuthState: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            notificationServiceProvider.overrideWithValue(
              NotificationService(),
            ),
            householdGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kunish Kitchen'), findsNWidgets(2));
      await tester.tap(find.text('邀请成员'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '成员邮箱'),
        ' member@example.com ',
      );
      await tester.tap(find.text('发送邀请'));
      await tester.pumpAndSettle();

      expect(gateway.inviteHouseholdId, 'household_1');
      expect(gateway.inviteEmail, 'member@example.com');
      expect(find.text('邀请已创建'), findsOneWidget);
      expect(find.text('member@example.com'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
    },
  );
}
