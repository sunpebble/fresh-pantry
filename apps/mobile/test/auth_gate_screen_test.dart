import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/screens/auth_gate_screen.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  FakeHouseholdGateway({this.initialHouseholds = const []});

  final authStateController = StreamController<void>.broadcast();
  List<Household> initialHouseholds;
  var sentEmail = '';

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {
    sentEmail = email;
  }

  @override
  Future<List<Household>> loadHouseholds() async => initialHouseholds;

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  void emitAuthStateChange() {
    authStateController.add(null);
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  testWidgets(
    'AuthGateScreen renders email OTP form when no household is loaded',
    (tester) async {
      await tester.pumpWidget(_wrap(FakeHouseholdGateway()));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '发送登录链接'), findsOneWidget);
      expect(find.text('App Shell'), findsNothing);
    },
  );

  testWidgets('AuthGateScreen sends trimmed OTP email', (tester) async {
    final gateway = FakeHouseholdGateway();
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' owner@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, '发送登录链接'));
    await tester.pumpAndSettle();

    expect(gateway.sentEmail, 'owner@example.com');
  });

  testWidgets(
    'AuthGateScreen shows authenticated child after households load',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FakeHouseholdGateway(
            initialHouseholds: const [
              Household(
                id: 'household_1',
                name: 'Home',
                ownerId: 'owner_1',
                defaultStorageArea: 'fridge',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
    },
  );

  testWidgets(
    'AuthGateScreen shows authenticated child after auth state changes',
    (tester) async {
      final gateway = FakeHouseholdGateway();
      await tester.pumpWidget(_wrap(gateway));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);

      gateway.initialHouseholds = const [
        Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      ];
      gateway.emitAuthStateChange();
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);

      await gateway.close();
    },
  );

  testWidgets('FreshPantryApp defaults to AuthGateScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AuthGateScreen), findsOneWidget);
    expect(find.text('登录 Fresh Pantry'), findsOneWidget);
  });
}

Widget _wrap(FakeHouseholdGateway gateway) {
  return ProviderScope(
    overrides: [householdGatewayProvider.overrideWithValue(gateway)],
    child: const MaterialApp(
      home: AuthGateScreen(authenticatedChild: Text('App Shell')),
    ),
  );
}
