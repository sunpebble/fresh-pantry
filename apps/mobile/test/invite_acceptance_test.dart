import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

class InviteRecordingGateway implements HouseholdGateway {
  final authStateController = StreamController<void>.broadcast();
  final households = <Household>[
    const Household(
      id: 'household_1',
      name: 'Home',
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    ),
  ];
  final members = <HouseholdMember>[
    const HouseholdMember(
      householdId: 'household_1',
      userId: 'owner_1',
      role: 'owner',
      email: 'owner@example.com',
    ),
  ];
  var acceptedToken = '';
  var inviteHouseholdId = '';
  var inviteEmail = '';
  var loadCount = 0;
  var pendingLoadCount = 0;
  var previewedToken = '';
  var acceptedInviteId = '';
  final pendingInvites = <HouseholdInvitePreview>[];
  Object? acceptInviteError;
  Object? createInviteError;
  Object? previewInviteError;

  @override
  bool get isAuthenticated => true;

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<List<Household>> loadHouseholds() async {
    loadCount += 1;
    return households;
  }

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  @override
  Future<String> createInvite({
    required String householdId,
    String? email,
  }) async {
    if (createInviteError != null) throw createInviteError!;
    inviteHouseholdId = householdId;
    inviteEmail = email ?? '';
    return 'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-';
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    return members
        .where((member) => member.householdId == householdId)
        .toList(growable: false);
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    if (previewInviteError != null) throw previewInviteError!;
    previewedToken = token;
    return const HouseholdInvitePreview(
      householdId: 'household_1',
      householdName: 'Kunish Kitchen',
      ownerEmail: 'owner@example.com',
      invitedEmail: 'member@example.com',
      memberCount: 2,
      inventoryCount: 3,
      shoppingCount: 1,
      customRecipeCount: 4,
    );
  }

  @override
  Future<void> acceptInvite(String token) async {
    if (acceptInviteError != null) throw acceptInviteError!;
    acceptedToken = token;
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    pendingLoadCount += 1;
    return pendingInvites;
  }

  @override
  Future<void> acceptInviteById(String inviteId) async {
    acceptedInviteId = inviteId;
  }

  @override
  String? get currentUserId => 'owner_1';

  @override
  Future<void> removeMember(String targetUserId) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> revokeInvite(String inviteId) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> updateHouseholdName(String householdId, String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) {
    throw UnimplementedError('Not needed by these tests.');
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('createInvite trims email before delegating', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    final inviteUrl = await controller.createInvite(
      'household_1',
      email: ' member@example.com ',
    );

    expect(
      inviteUrl,
      'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-',
    );
    expect(gateway.inviteHouseholdId, 'household_1');
    expect(gateway.inviteEmail, 'member@example.com');
    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('createInvite supports open household links without email', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    final inviteUrl = await controller.createInvite('household_1');

    expect(inviteUrl, contains('/invite/'));
    expect(gateway.inviteHouseholdId, 'household_1');
    expect(gateway.inviteEmail, isEmpty);
    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('previewInvite trims token and stores household overview', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    final preview = await controller.previewInvite(' abcDEF123_- ');

    expect(gateway.previewedToken, 'abcDEF123_-');
    expect(preview.householdName, 'Kunish Kitchen');
    expect(controller.state.invitePreview?.ownerEmail, 'owner@example.com');
    expect(controller.state.invitePreview?.inventoryCount, 3);
    expect(controller.state.isPreviewLoading, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('acceptInvite trims token and refreshes households', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.acceptInvite(' abcDEF123_- ');

    expect(gateway.acceptedToken, 'abcDEF123_-');
    expect(gateway.loadCount, 1);
    expect(controller.state.households.single.id, 'household_1');
    expect(controller.state.householdMembers.single.email, 'owner@example.com');
    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('acceptInvite exposes gateway errors', () async {
    final gateway = InviteRecordingGateway()
      ..acceptInviteError = StateError('invite unavailable');
    final controller = HouseholdSessionController(gateway);

    await controller.acceptInvite('abcDEF123_-');

    expect(controller.state.error, contains('invite unavailable'));
    expect(controller.state.isSubmitting, isFalse);
    expect(gateway.loadCount, 0);

    controller.dispose();
    await gateway.close();
  });

  test('refreshHouseholds loads pending invite reminders', () async {
    final gateway = InviteRecordingGateway()
      ..pendingInvites.add(
        HouseholdInvitePreview.fromJson({
          'invite_id': 'invite_1',
          'household_id': 'household_2',
          'household_name': 'Kunish Shared Kitchen',
          'owner_email': 'owner@example.com',
          'invited_email': 'member@example.com',
          'member_count': 2,
          'inventory_count': 5,
          'shopping_count': 3,
          'custom_recipe_count': 1,
        }),
      );
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(gateway.pendingLoadCount, 1);
    final pending =
        (controller.state as dynamic).pendingInvitePreviews
            as List<HouseholdInvitePreview>;
    expect(pending.single.householdName, 'Kunish Shared Kitchen');

    controller.dispose();
    await gateway.close();
  });

  test(
    'acceptInviteById accepts reminder and refreshes household state',
    () async {
      final gateway = InviteRecordingGateway()
        ..pendingInvites.add(
          HouseholdInvitePreview.fromJson({
            'invite_id': 'invite_1',
            'household_id': 'household_2',
            'household_name': 'Kunish Shared Kitchen',
            'owner_email': 'owner@example.com',
            'invited_email': 'member@example.com',
            'member_count': 2,
            'inventory_count': 5,
            'shopping_count': 3,
            'custom_recipe_count': 1,
          }),
        );
      final controller = HouseholdSessionController(gateway);

      await (controller as dynamic).acceptInviteById(' invite_1 ');

      expect(gateway.acceptedInviteId, 'invite_1');
      expect(gateway.loadCount, 1);
      expect(gateway.pendingLoadCount, 1);
      expect((controller.state as dynamic).pendingInvitePreviews, isEmpty);
      expect(controller.state.households.single.id, 'household_1');
      expect(
        controller.state.householdMembers.single.email,
        'owner@example.com',
      );
      expect(controller.state.isSubmitting, isFalse);

      controller.dispose();
      await gateway.close();
    },
  );
}
