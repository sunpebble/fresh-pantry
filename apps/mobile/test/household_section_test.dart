import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/widgets/settings/household_section.dart';

void main() {
  testWidgets('HouseholdSection renders members and invite action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'owner_1',
                role: 'owner',
                email: 'owner@example.com',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Kunish Kitchen'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('邀请成员'), findsOneWidget);
  });
}
