import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

const stubInviteUrl =
    'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-';

class HouseholdGatewayStub implements HouseholdGateway {
  HouseholdGatewayStub({
    List<Household> households = const [],
    List<HouseholdMember> members = const [],
    List<HouseholdInvitePreview> pendingInvites = const [],
    this.inviteUrl = stubInviteUrl,
    this.isAuthenticated = false,
    bool emitInitialAuthState = false,
  }) : households = List<Household>.of(households),
       members = List<HouseholdMember>.of(members),
       _pendingInvites = List<HouseholdInvitePreview>.of(pendingInvites),
       _authStateChanges = emitInitialAuthState
           ? Stream<void>.value(null)
           : const Stream<void>.empty();

  final List<Household> households;
  final List<HouseholdMember> members;
  final List<HouseholdInvitePreview> _pendingInvites;
  final String inviteUrl;
  @override
  final bool isAuthenticated;
  final Stream<void> _authStateChanges;
  var inviteHouseholdId = '';
  var inviteEmail = '';
  var acceptedToken = '';
  var acceptedInviteId = '';

  @override
  Stream<void> get authStateChanges => _authStateChanges;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<void> verifyEmailOtp(String email, String token) async {}

  @override
  Future<List<Household>> loadHouseholds() async {
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
    inviteHouseholdId = householdId;
    inviteEmail = email ?? '';
    return inviteUrl;
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    return members
        .where((member) => member.householdId == householdId)
        .toList(growable: false);
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    return const HouseholdInvitePreview(
      householdId: 'household_1',
      householdName: 'Kunish Kitchen',
      ownerEmail: 'owner@example.com',
      invitedEmail: 'member@example.com',
      memberCount: 1,
      inventoryCount: 0,
      shoppingCount: 0,
      customRecipeCount: 0,
    );
  }

  @override
  Future<void> acceptInvite(String token) async {
    acceptedToken = token;
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    return _pendingInvites;
  }

  @override
  Future<void> acceptInviteById(String inviteId) async {
    acceptedInviteId = inviteId;
  }

  @override
  String? get currentUserId => 'owner_1';

  var removedUserId = '';
  var revokedInviteId = '';
  var dissolvedHouseholdId = '';
  Object? dissolveHouseholdError;
  final ownerPendingInvites = <OwnerPendingInvite>[];

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    removedUserId = userId;
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
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

  @override
  Future<void> leaveHousehold(String householdId) async {
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

  @override
  Future<void> updateHouseholdName(String householdId, String name) async {
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
}
