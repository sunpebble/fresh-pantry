import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/screens/household_screen.dart';
import 'helpers/household_gateway_stub.dart';

void main() {
  testWidgets('HouseholdScreen renders current household and members', (tester) async {
    final stub = HouseholdGatewayStub(
      isAuthenticated: true,
      households: const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_1', defaultStorageArea: 'fridge'),
      ],
      members: const [
        HouseholdMember(householdId: 'h1', userId: 'owner_1', role: 'owner', email: 'me@ex.com'),
      ],
    );
    final controller = HouseholdSessionController(stub);
    await controller.refreshHouseholds();
    await controller.switchHousehold('h1');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        householdSessionControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: HouseholdScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('我家'), findsOneWidget);
    expect(find.text('me@ex.com'), findsOneWidget);
  });
}
