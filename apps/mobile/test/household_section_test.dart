import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/widgets/settings/household_section.dart';

void main() {
  testWidgets('HouseholdSection renders members and invite action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
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
            isOwner: true,
            onInviteLink: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Kunish Kitchen'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('扫码/链接邀请'), findsOneWidget);
  });

  testWidgets('HouseholdSection shows dismissible on member rows for owner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
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
            isOwner: true,
            currentUserId: 'owner_1',
            onRemoveMember: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byType(Dismissible), findsOneWidget);
  });

  testWidgets('HouseholdSection hides dismissible on own row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'owner_1',
                role: 'owner',
                email: 'owner@example.com',
              ),
            ],
            isOwner: true,
            currentUserId: 'owner_1',
            onRemoveMember: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('HouseholdSection shows pending invites when owner has them', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'owner_1',
                role: 'owner',
                email: 'owner@example.com',
              ),
            ],
            isOwner: true,
            currentUserId: 'owner_1',
            ownerPendingInvites: [
              OwnerPendingInvite(
                id: 'invite_1',
                email: 'pending@example.com',
                expiresAt: DateTime.now().add(const Duration(days: 7)),
                createdAt: DateTime.now(),
              ),
            ],
            onRevokeInvite: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('待处理邀请'), findsOneWidget);
    expect(find.text('pending@example.com'), findsOneWidget);
  });

  testWidgets('HouseholdSection labels open pending invites as scan links', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            isOwner: true,
            currentUserId: 'owner_1',
            ownerPendingInvites: [
              OwnerPendingInvite(
                id: 'invite_1',
                email: '',
                expiresAt: DateTime.now().add(const Duration(days: 7)),
                createdAt: DateTime.now(),
              ),
            ],
            onRevokeInvite: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('待处理邀请'), findsOneWidget);
    expect(find.text('扫码/链接邀请'), findsOneWidget);
  });

  testWidgets('HouseholdSection hides invite actions for non-owners', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            isOwner: false,
            onInviteLink: () async {},
            onInviteEmail: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('扫码/链接邀请'), findsNothing);
    expect(find.text('邮箱定向邀请'), findsNothing);
  });

  testWidgets('HouseholdSection hides pending invites section when empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            isOwner: true,
            currentUserId: 'owner_1',
            onRevokeInvite: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('待处理邀请'), findsNothing);
  });

  testWidgets('HouseholdSection dropdown renders all households', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Home',
            members: const [],
            households: const [
              Household(
                id: 'h1',
                name: 'Home',
                ownerId: 'o1',
                defaultStorageArea: 'fridge',
              ),
              Household(
                id: 'h2',
                name: 'Office',
                ownerId: 'o1',
                defaultStorageArea: 'pantry',
              ),
            ],
            selectedHouseholdId: 'h1',
            onSwitchHousehold: (id) {},
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets('HouseholdSection shows static name when single household', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Solo Kitchen',
            members: [],
            households: [
              Household(
                id: 'h1',
                name: 'Solo Kitchen',
                ownerId: 'o1',
                defaultStorageArea: 'fridge',
              ),
            ],
            selectedHouseholdId: 'h1',
          ),
        ),
      ),
    );

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Solo Kitchen'), findsOneWidget);
  });

  testWidgets('HouseholdSection shows edit icon for owner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'owner_1',
                role: 'owner',
                email: 'owner@example.com',
              ),
            ],
            isOwner: true,
            currentUserId: 'owner_1',
            onEditName: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('HouseholdSection hides edit icon for non-owner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'member_1',
                role: 'member',
                email: 'member@example.com',
              ),
            ],
            isOwner: false,
            currentUserId: 'member_1',
            onEditName: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
