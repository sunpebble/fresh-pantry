import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  final households = <Household>[];
  final members = <HouseholdMember>[];
  final pendingInvites = <HouseholdInvitePreview>[];
  final authStateController = StreamController<void>.broadcast();
  @override
  var isAuthenticated = false;
  var sentEmail = '';
  var verifiedEmail = '';
  var verifiedToken = '';
  Object? sendOtpError;
  Object? verifyOtpError;
  Object? loadHouseholdsError;
  Object? loadHouseholdMembersError;
  Completer<void>? sendOtpCompleter;
  var acceptedInviteToken = '';

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {
    if (sendOtpError != null) throw sendOtpError!;
    sentEmail = email;
    await sendOtpCompleter?.future;
  }

  @override
  Future<void> verifyEmailOtp(String email, String token) async {
    if (verifyOtpError != null) throw verifyOtpError!;
    verifiedEmail = email;
    verifiedToken = token;
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    if (loadHouseholdsError != null) throw loadHouseholdsError!;
    return households;
  }

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    if (loadHouseholdMembersError != null) throw loadHouseholdMembersError!;
    return members
        .where((member) => member.householdId == householdId)
        .toList(growable: false);
  }

  HouseholdInvitePreview? invitePreviewResult;

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    final result = invitePreviewResult;
    if (result == null) {
      throw UnimplementedError('Not needed by these tests.');
    }
    return result;
  }

  @override
  Future<void> acceptInvite(String token) async {
    acceptedInviteToken = token;
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    return pendingInvites;
  }

  @override
  Future<void> acceptInviteById(String inviteId) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  String? get currentUserId => 'owner_1';

  var removedUserId = '';
  var removedFromHouseholdId = '';
  var revokedInviteId = '';
  var dissolvedHouseholdId = '';
  final ownerPendingInvites = <OwnerPendingInvite>[];
  Object? removeMemberError;
  Object? revokeInviteError;
  Object? dissolveHouseholdError;

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    if (removeMemberError != null) throw removeMemberError!;
    removedFromHouseholdId = householdId;
    removedUserId = userId;
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    if (revokeInviteError != null) throw revokeInviteError!;
    revokedInviteId = inviteId;
  }

  @override
  Future<void> dissolveHousehold(String householdId) async {
    if (dissolveHouseholdError != null) throw dissolveHouseholdError!;
    dissolvedHouseholdId = householdId;
    households.removeWhere((household) => household.id == householdId);
    members.removeWhere((member) => member.householdId == householdId);
  }

  var leftHouseholdId = '';
  Object? leaveHouseholdError;

  @override
  Future<void> leaveHousehold(String householdId) async {
    if (leaveHouseholdError != null) throw leaveHouseholdError!;
    leftHouseholdId = householdId;
    households.removeWhere((household) => household.id == householdId);
    members.removeWhere(
      (member) =>
          member.householdId == householdId && member.userId == currentUserId,
    );
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) async {
    return ownerPendingInvites;
  }

  var updatedHouseholdName = '';
  var updatedHouseholdId = '';
  Map<String, dynamic>? updatedCategoryPreferences;
  Object? updateHouseholdNameError;

  @override
  Future<void> updateHouseholdName(String householdId, String name) async {
    if (updateHouseholdNameError != null) throw updateHouseholdNameError!;
    updatedHouseholdId = householdId;
    updatedHouseholdName = name;
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) async {
    updatedHouseholdId = householdId;
    updatedCategoryPreferences = preferences;
  }

  void emitAuthStateChange() {
    authStateController.add(null);
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('sendOtp trims email before sending', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp(' owner@example.com ');

    expect(gateway.sentEmail, 'owner@example.com');
    expect(controller.state.email, 'owner@example.com');
    expect(controller.state.isSubmitting, isFalse);
  });

  test('sendOtp exposes gateway errors in state', () async {
    final gateway = FakeHouseholdGateway()..sendOtpError = StateError('boom');
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp('owner@example.com');

    expect(controller.state.error, contains('boom'));
    expect(controller.state.isSubmitting, isFalse);
  });

  test('verifyOtp verifies the trimmed code against the sent email', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp('owner@example.com');
    await controller.verifyOtp('  123456  ');

    expect(gateway.verifiedEmail, 'owner@example.com');
    expect(gateway.verifiedToken, '123456');
    expect(controller.state.isSubmitting, isFalse);
    expect(controller.state.error, isNull);
  });

  test('verifyOtp surfaces gateway errors in state', () async {
    final gateway = FakeHouseholdGateway()
      ..verifyOtpError = StateError('bad code');
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp('owner@example.com');
    await controller.verifyOtp('000000');

    expect(controller.state.error, contains('bad code'));
    expect(controller.state.isSubmitting, isFalse);
  });

  test('verifyOtp requires a previously sent code', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.verifyOtp('123456');

    expect(gateway.verifiedToken, isEmpty);
    expect(controller.state.error, isNotNull);
  });

  test('refreshHouseholds stores loaded households', () async {
    final gateway = FakeHouseholdGateway()
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.households.single.id, 'household_1');
  });

  test('refreshHouseholds stores members for the loaded household', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      )
      ..members.addAll(const [
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
      ]);
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.householdMembers.map((member) => member.email), [
      'owner@example.com',
      'member@example.com',
    ]);
  });

  test('refreshHouseholds stores authentication state', () async {
    final gateway = FakeHouseholdGateway()..isAuthenticated = true;
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.isAuthenticated, isTrue);
  });

  test('refreshHouseholds exposes gateway errors in state', () async {
    final gateway = FakeHouseholdGateway()
      ..loadHouseholdsError = StateError('offline');
    final controller = HouseholdSessionController(gateway);

    await controller.refreshHouseholds();

    expect(controller.state.error, contains('offline'));
    expect(controller.state.households, isEmpty);
  });

  test('auth state changes refresh households', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    gateway.households.add(
      const Household(
        id: 'household_1',
        name: 'Home',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    );
    gateway.emitAuthStateChange();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.households.single.id, 'household_1');

    controller.dispose();
    await gateway.close();
  });

  test('refreshHouseholds preserves active OTP submission', () async {
    final gateway = FakeHouseholdGateway()
      ..sendOtpCompleter = Completer<void>()
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);

    final sendOtpFuture = controller.sendOtp('owner@example.com');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isSubmitting, isTrue);

    await controller.refreshHouseholds();

    expect(controller.state.isSubmitting, isTrue);
    expect(controller.state.households.single.id, 'household_1');

    gateway.sendOtpCompleter!.complete();
    await sendOtpFuture;

    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('removeMember calls gateway and refreshes members', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      )
      ..members.addAll(const [
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
      ]);
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.removeMember('household_1', 'member_1');

    expect(gateway.removedFromHouseholdId, 'household_1');
    expect(gateway.removedUserId, 'member_1');
  });

  test('removeMember exposes error in state on failure', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      )
      ..removeMemberError = StateError('not authorized');
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.removeMember('household_1', 'member_1');

    expect(controller.state.error, contains('not authorized'));
  });

  test(
    'revokeInvite calls gateway and refreshes owner pending invites',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.add(
          const Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
        )
        ..ownerPendingInvites.addAll([
          OwnerPendingInvite(
            id: 'invite_1',
            email: 'pending@example.com',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
            createdAt: DateTime.now(),
          ),
        ]);
      final controller = HouseholdSessionController(gateway);
      await controller.refreshHouseholds();

      await controller.revokeInvite('household_1', 'invite_1');

      expect(gateway.revokedInviteId, 'invite_1');
    },
  );

  test('revokeInvite exposes error in state on failure', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      )
      ..revokeInviteError = StateError('not authorized');
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.revokeInvite('household_1', 'invite_1');

    expect(controller.state.error, contains('not authorized'));
  });

  test(
    'dissolveHousehold calls gateway and selects the next household',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.addAll(const [
          Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
          Household(
            id: 'household_2',
            name: 'Office',
            ownerId: 'owner_1',
            defaultStorageArea: 'pantry',
          ),
        ])
        ..members.addAll(const [
          HouseholdMember(
            householdId: 'household_1',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
          HouseholdMember(
            householdId: 'household_2',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
          HouseholdMember(
            householdId: 'household_2',
            userId: 'member_2',
            role: 'member',
            email: 'colleague@example.com',
          ),
        ]);
      final controller = HouseholdSessionController(gateway);
      await controller.refreshHouseholds();

      await controller.dissolveHousehold('household_1');

      expect(gateway.dissolvedHouseholdId, 'household_1');
      expect(controller.state.households.map((household) => household.id), [
        'household_2',
      ]);
      expect(controller.state.selectedHouseholdId, 'household_2');
      expect(controller.state.householdMembers.map((member) => member.email), [
        'owner@example.com',
        'colleague@example.com',
      ]);
      expect(controller.state.isSubmitting, isFalse);
    },
  );

  test(
    'dissolveHousehold clears selection when the last household is deleted',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.add(
          const Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
        )
        ..members.add(
          const HouseholdMember(
            householdId: 'household_1',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
        );
      final controller = HouseholdSessionController(gateway);
      await controller.refreshHouseholds();

      await controller.dissolveHousehold('household_1');

      expect(controller.state.households, isEmpty);
      expect(controller.state.selectedHouseholdId, isEmpty);
      expect(controller.state.householdMembers, isEmpty);
    },
  );

  test('dissolveHousehold exposes error in state on failure', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      )
      ..dissolveHouseholdError = StateError('not authorized');
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.dissolveHousehold('household_1');

    expect(controller.state.error, contains('not authorized'));
    expect(controller.state.isSubmitting, isFalse);
  });

  test(
    'switchHousehold updates selectedHouseholdId and reloads members',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.addAll(const [
          Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
          Household(
            id: 'household_2',
            name: 'Office',
            ownerId: 'owner_1',
            defaultStorageArea: 'pantry',
          ),
        ])
        ..members.addAll(const [
          HouseholdMember(
            householdId: 'household_1',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
          HouseholdMember(
            householdId: 'household_2',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
          HouseholdMember(
            householdId: 'household_2',
            userId: 'member_2',
            role: 'member',
            email: 'colleague@example.com',
          ),
        ]);
      final controller = HouseholdSessionController(gateway);
      await controller.refreshHouseholds();

      expect(controller.state.selectedHouseholdId, 'household_1');

      await controller.switchHousehold('household_2');

      expect(controller.state.selectedHouseholdId, 'household_2');
      expect(controller.state.householdMembers.map((m) => m.email), [
        'owner@example.com',
        'colleague@example.com',
      ]);
    },
  );

  test(
    'switchHousehold restores previous selection when loading members fails',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.addAll(const [
          Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
          Household(
            id: 'household_2',
            name: 'Office',
            ownerId: 'owner_1',
            defaultStorageArea: 'pantry',
          ),
        ])
        ..members.add(
          const HouseholdMember(
            householdId: 'household_1',
            userId: 'owner_1',
            role: 'owner',
            email: 'owner@example.com',
          ),
        );
      final controller = HouseholdSessionController(gateway);
      await controller.refreshHouseholds();

      expect(controller.state.selectedHouseholdId, 'household_1');

      gateway.loadHouseholdMembersError = StateError('offline');
      await controller.switchHousehold('household_2');

      expect(controller.state.error, contains('offline'));
      expect(controller.state.selectedHouseholdId, 'household_1');
      expect(controller.state.isLoading, isFalse);
    },
  );

  test(
    'acceptInvite excludes the accepted invite despite replication lag',
    () async {
      const joinedHousehold = Household(
        id: 'household_2',
        name: 'Office',
        ownerId: 'owner_2',
        defaultStorageArea: 'pantry',
      );
      const accepted = HouseholdInvitePreview(
        inviteId: 'invite_2',
        householdId: 'household_2',
        householdName: 'Office',
        ownerEmail: 'owner2@example.com',
        invitedEmail: '',
        memberCount: 1,
        inventoryCount: 0,
        shoppingCount: 0,
        customRecipeCount: 0,
      );
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = true
        ..households.add(joinedHousehold)
        ..invitePreviewResult = accepted
        // Read-after-write lag: backend still lists the accepted invite.
        ..pendingInvites.add(accepted);
      final controller = HouseholdSessionController(gateway);

      await controller.previewInvite('token-2');
      expect(controller.state.invitePreview?.inviteId, 'invite_2');

      await controller.acceptInvite('token-2');

      expect(gateway.acceptedInviteToken, 'token-2');
      expect(controller.state.selectedHouseholdId, 'household_2');
      expect(
        controller.state.pendingInvitePreviews.map((invite) => invite.inviteId),
        isNot(contains('invite_2')),
      );
    },
  );

  test('sendOtp records the sent email on success', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp(' owner@example.com ');

    expect(controller.state.sentOtpToEmail, 'owner@example.com');
  });

  test('sendOtp clears sent email on failure', () async {
    final gateway = FakeHouseholdGateway()..sendOtpError = StateError('boom');
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp('owner@example.com');

    expect(controller.state.sentOtpToEmail, isEmpty);
  });

  test(
    'refreshOwnerPendingInvites clears invites and skips gateway when signed out',
    () async {
      final gateway = FakeHouseholdGateway()
        ..isAuthenticated = false
        ..ownerPendingInvites.add(
          OwnerPendingInvite(
            id: 'invite_1',
            email: 'pending@example.com',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
            createdAt: DateTime.now(),
          ),
        );
      final controller = HouseholdSessionController(gateway);

      await controller.refreshOwnerPendingInvites('household_1');

      expect(controller.state.ownerPendingInvites, isEmpty);
      expect(controller.state.error, isNull);
    },
  );

  test('updateHouseholdName calls gateway and refreshes households', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Old Name',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.updateHouseholdName('household_1', 'New Name');

    expect(gateway.updatedHouseholdId, 'household_1');
    expect(gateway.updatedHouseholdName, 'New Name');
  });

  test('updateHouseholdName rejects empty name', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.updateHouseholdName('household_1', '  ');

    expect(controller.state.error, contains('不能为空'));
    expect(gateway.updatedHouseholdName, isEmpty);
  });

  test('updateCategoryPreferences calls gateway', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.add(
        const Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      );
    final controller = HouseholdSessionController(gateway);
    await controller.refreshHouseholds();

    await controller.updateCategoryPreferences('household_1', {'高蛋白': true});

    expect(gateway.updatedHouseholdId, 'household_1');
    expect(gateway.updatedCategoryPreferences, {'高蛋白': true});
  });

  test('leaveHousehold re-selects another household after leaving', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.addAll(const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
        Household(id: 'h2', name: '李家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
      ])
      ..members.addAll(const [
        HouseholdMember(householdId: 'h2', userId: 'owner_1', role: 'member', email: 'me@ex.com'),
      ]);
    final controller = HouseholdSessionController(gateway);
    addTearDown(controller.dispose);
    await controller.switchHousehold('h1');

    final ok = await controller.leaveHousehold('h1');

    expect(ok, isTrue);
    expect(gateway.leftHouseholdId, 'h1');
    expect(controller.state.households.map((h) => h.id), ['h2']);
    expect(controller.state.selectedHouseholdId, 'h2');
    expect(controller.state.error, isNull);
    expect(controller.state.isSubmitting, isFalse);
  });

  test('leaveHousehold surfaces error and keeps selection on failure', () async {
    final gateway = FakeHouseholdGateway()
      ..isAuthenticated = true
      ..households.addAll(const [
        Household(id: 'h1', name: '我家', ownerId: 'owner_2', defaultStorageArea: 'fridge'),
      ])
      ..leaveHouseholdError = StateError('sole owner');
    final controller = HouseholdSessionController(gateway);
    addTearDown(controller.dispose);
    await controller.switchHousehold('h1');

    final ok = await controller.leaveHousehold('h1');

    expect(ok, isFalse);
    expect(controller.state.error, isNotNull);
    expect(controller.state.selectedHouseholdId, 'h1');
  });
}
