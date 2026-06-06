import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_client_provider.dart';
import '../providers/storage_service_provider.dart';
import '../storage/custom_recipe_repo.dart';
import '../storage/inventory_repo.dart';
import '../storage/shopping_repo.dart';
import '../sync/remote_pantry_repository.dart';
import '../sync/sync_ids.dart';
import '../sync/sync_providers.dart';
import 'household_models.dart';

const supabaseAuthRedirectUrl = 'com.kunish.freshpantry://signin-callback/';
const _preserveError = Object();
const _preserveInvitePreview = Object();

@visibleForTesting
String resolveSupabaseAuthRedirectUrl({bool isWeb = kIsWeb, Uri? webBaseUri}) {
  if (!isWeb) return supabaseAuthRedirectUrl;

  final uri = webBaseUri ?? Uri.base;
  if (uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasAuthority) {
    return '${uri.scheme}://${uri.authority}/';
  }

  return supabaseAuthRedirectUrl;
}

abstract class HouseholdGateway {
  Stream<void> get authStateChanges;
  bool get isAuthenticated;
  String? get currentUserId;

  Future<void> sendOtp(String email);
  Future<void> verifyEmailOtp(String email, String token);
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<void> uploadInitialData(String householdId);
  Future<String> createInvite({required String householdId, String? email});
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId);
  Future<List<HouseholdInvitePreview>> loadPendingInvites();
  Future<HouseholdInvitePreview> previewInvite(String token);
  Future<void> acceptInvite(String token);
  Future<void> acceptInviteById(String inviteId);
  Future<void> removeMember({
    required String householdId,
    required String userId,
  });
  Future<void> revokeInvite(String inviteId);
  Future<void> dissolveHousehold(String householdId);
  Future<void> leaveHousehold(String householdId);
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
  Future<void> updateHouseholdName(String householdId, String name);
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  );
}

class SupabaseHouseholdGateway implements HouseholdGateway {
  SupabaseHouseholdGateway(
    this._client,
    this._remoteRepository,
    this._inventoryRepo,
    this._shoppingRepo,
    this._customRecipeRepo,
  );

  final SupabaseClient _client;
  final RemotePantryRepository _remoteRepository;
  final InventoryRepo _inventoryRepo;
  final ShoppingRepo _shoppingRepo;
  final CustomRecipeRepo _customRecipeRepo;

  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<void> get authStateChanges {
    return _client.auth.onAuthStateChange
        .where((data) {
          return switch (data.event) {
            AuthChangeEvent.initialSession ||
            AuthChangeEvent.signedIn ||
            AuthChangeEvent.signedOut => true,
            _ => false,
          };
        })
        .map((_) {});
  }

  @override
  Future<void> sendOtp(String email) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: resolveSupabaseAuthRedirectUrl(),
    );
  }

  @override
  Future<void> verifyEmailOtp(String email, String token) async {
    // Code entry verifies against /verify directly and returns a session — it
    // never relies on the deep-link round trip or the PKCE code exchange, which
    // is exactly why we moved off the magic link (the link's code was reaching
    // the app but never getting exchanged; see the auth-callback diagnosis).
    //
    // Existing users get a magic-link email (OtpType.email); a brand-new user's
    // first code comes from the signup-confirmation email and only verifies under
    // OtpType.signup. A wrong-type attempt errors WITHOUT consuming a valid token,
    // so we fall back to signup before surfacing the failure.
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
    } on AuthException {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );
    }
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    if (_client.auth.currentUser == null) return const [];
    return _remoteRepository.loadHouseholds();
  }

  @override
  Future<Household> createHousehold(String name) {
    return _remoteRepository.createHousehold(name);
  }

  @override
  Future<void> uploadInitialData(String householdId) async {
    final inventory = _inventoryRepo
        .loadAll()
        .map((item) {
          return isUuid(item.id) ? item : item.copyWith(id: newSyncEntityId());
        })
        .toList(growable: false);
    final shopping = _shoppingRepo
        .loadAll()
        .map((item) {
          return isUuid(item.id) ? item : item.copyWith(id: newSyncEntityId());
        })
        .toList(growable: false);
    final customRecipes = _customRecipeRepo
        .loadAll()
        .map((recipe) {
          return isUuid(recipe.id)
              ? recipe
              : recipe.copyWith(id: newSyncEntityId());
        })
        .toList(growable: false);

    await _inventoryRepo.saveItems(householdId, inventory);
    await _shoppingRepo.saveItems(householdId, shopping);
    await _customRecipeRepo.saveRecipes(householdId, customRecipes);

    // Adoption moves local-only ('' scope) rows into the household. Without
    // removing the originals they linger as duplicate orphans that later sync
    // passes keep re-minting into fresh ids. Purge them once migrated.
    if (householdId.isNotEmpty) {
      await _inventoryRepo.deleteHouseholdScope('');
      await _shoppingRepo.deleteHouseholdScope('');
      await _customRecipeRepo.deleteHouseholdScope('');
    }

    await _remoteRepository.upsertInventory(
      householdId,
      inventory.map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertShopping(
      householdId,
      shopping.map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertCustomRecipes(
      householdId,
      customRecipes.map((recipe) => recipe.toJson()).toList(),
    );
  }

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    return _remoteRepository.createInvite(
      householdId: householdId,
      email: email,
    );
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) {
    if (_client.auth.currentUser == null) return Future.value(const []);
    return _remoteRepository.loadHouseholdMembers(householdId);
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() {
    return _remoteRepository.loadPendingInvites();
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) {
    return _remoteRepository.previewInvite(token);
  }

  @override
  Future<void> acceptInvite(String token) {
    return _remoteRepository.acceptInvite(token);
  }

  @override
  Future<void> acceptInviteById(String inviteId) {
    return _remoteRepository.acceptInviteById(inviteId);
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) {
    return _remoteRepository.removeMember(
      householdId: householdId,
      userId: userId,
    );
  }

  @override
  Future<void> leaveHousehold(String householdId) {
    return _remoteRepository.leaveHousehold(householdId);
  }

  @override
  Future<void> revokeInvite(String inviteId) {
    return _remoteRepository.revokeInvite(inviteId);
  }

  @override
  Future<void> dissolveHousehold(String householdId) {
    return _remoteRepository.dissolveHousehold(householdId);
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) {
    return _remoteRepository.fetchOwnerPendingInvites(householdId);
  }

  @override
  Future<void> updateHouseholdName(String householdId, String name) {
    return _remoteRepository.updateHouseholdName(householdId, name);
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) {
    return _remoteRepository.updateCategoryPreferences(
      householdId,
      preferences,
    );
  }
}

class HouseholdSessionState {
  const HouseholdSessionState({
    this.email = '',
    this.currentUserId = '',
    this.selectedHouseholdId = '',
    this.sentOtpToEmail = '',
    this.isLoading = true,
    this.isSubmitting = false,
    this.isPreviewLoading = false,
    this.isPendingInvitesLoading = false,
    this.isAuthenticated = false,
    this.error,
    this.households = const [],
    this.householdMembers = const [],
    this.pendingInvitePreviews = const [],
    this.ownerPendingInvites = const [],
    this.invitePreview,
  });

  final String email;
  final String currentUserId;
  final String selectedHouseholdId;
  final String sentOtpToEmail;
  final bool isLoading;
  final bool isSubmitting;
  final bool isPreviewLoading;
  final bool isPendingInvitesLoading;
  final bool isAuthenticated;
  final String? error;
  final List<Household> households;
  final List<HouseholdMember> householdMembers;
  final List<HouseholdInvitePreview> pendingInvitePreviews;
  final List<OwnerPendingInvite> ownerPendingInvites;
  final HouseholdInvitePreview? invitePreview;

  HouseholdSessionState copyWith({
    String? email,
    String? currentUserId,
    String? selectedHouseholdId,
    String? sentOtpToEmail,
    bool? isLoading,
    bool? isSubmitting,
    bool? isPreviewLoading,
    bool? isPendingInvitesLoading,
    bool? isAuthenticated,
    Object? error = _preserveError,
    List<Household>? households,
    List<HouseholdMember>? householdMembers,
    List<HouseholdInvitePreview>? pendingInvitePreviews,
    List<OwnerPendingInvite>? ownerPendingInvites,
    Object? invitePreview = _preserveInvitePreview,
  }) {
    return HouseholdSessionState(
      email: email ?? this.email,
      currentUserId: currentUserId ?? this.currentUserId,
      selectedHouseholdId: selectedHouseholdId ?? this.selectedHouseholdId,
      sentOtpToEmail: sentOtpToEmail ?? this.sentOtpToEmail,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isPreviewLoading: isPreviewLoading ?? this.isPreviewLoading,
      isPendingInvitesLoading:
          isPendingInvitesLoading ?? this.isPendingInvitesLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: identical(error, _preserveError) ? this.error : error as String?,
      households: households ?? this.households,
      householdMembers: householdMembers ?? this.householdMembers,
      pendingInvitePreviews:
          pendingInvitePreviews ?? this.pendingInvitePreviews,
      ownerPendingInvites: ownerPendingInvites ?? this.ownerPendingInvites,
      invitePreview: identical(invitePreview, _preserveInvitePreview)
          ? this.invitePreview
          : invitePreview as HouseholdInvitePreview?,
    );
  }
}

class HouseholdSessionController extends StateNotifier<HouseholdSessionState> {
  HouseholdSessionController(this._gateway)
    : super(const HouseholdSessionState()) {
    _authSubscription = _gateway.authStateChanges.listen(
      (_) => refreshHouseholds(),
      onError: (Object error, StackTrace stackTrace) {
        _setError(error);
      },
    );
  }

  final HouseholdGateway _gateway;
  StreamSubscription<void>? _authSubscription;
  int _refreshHouseholdsGeneration = 0;

  Future<void> sendOtp(String email) async {
    final trimmed = email.trim();
    state = state.copyWith(
      email: trimmed,
      isSubmitting: true,
      error: null,
      sentOtpToEmail: '',
    );
    try {
      await _gateway.sendOtp(trimmed);
      if (!mounted) return;
      state = state.copyWith(
        email: trimmed,
        isSubmitting: false,
        error: null,
        sentOtpToEmail: trimmed,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        email: trimmed,
        isSubmitting: false,
        error: error.toString(),
        sentOtpToEmail: '',
      );
    }
  }

  Future<void> verifyOtp(String token) async {
    final code = token.trim();
    final email = state.sentOtpToEmail;
    if (email.isEmpty) {
      state = state.copyWith(error: '请先获取验证码');
      return;
    }
    if (code.isEmpty) {
      state = state.copyWith(error: '请输入验证码');
      return;
    }
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.verifyEmailOtp(email, code);
      // On success the gateway emits AuthChangeEvent.signedIn, which the auth
      // subscription turns into refreshHouseholds() — that flips isAuthenticated
      // and drives the gate forward. Here we only drop the submitting flag.
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: null);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<void> refreshHouseholds() async {
    final generation = ++_refreshHouseholdsGeneration;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final currentSelectedId = state.selectedHouseholdId;
      final selectedId =
          (currentSelectedId.isNotEmpty &&
              households.any((h) => h.id == currentSelectedId))
          ? currentSelectedId
          : (households.isEmpty ? '' : households.first.id);
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted || generation != _refreshHouseholdsGeneration) return;
      state = state.copyWith(
        isLoading: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        currentUserId: _gateway.currentUserId ?? '',
        pendingInvitePreviews: isAuthenticated
            ? state.pendingInvitePreviews
            : const <HouseholdInvitePreview>[],
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
      }
    } catch (error) {
      if (generation != _refreshHouseholdsGeneration) return;
      _setError(error);
    }
  }

  Future<void> createHousehold(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: '家庭名称不能为空');
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final household = await _gateway.createHousehold(trimmed);
      await _gateway.uploadInitialData(household.id);
      final members = await _loadMembersForSelectedHousehold([
        household,
      ], household.id);
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: true,
        error: null,
        households: List.unmodifiable([household]),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: household.id,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<String> createInvite(String householdId, {String? email}) async {
    final trimmedEmail = email?.trim();
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final inviteUrl = await _gateway.createInvite(
        householdId: householdId,
        email: trimmedEmail == null || trimmedEmail.isEmpty
            ? null
            : trimmedEmail,
      );
      if (!mounted) return inviteUrl;
      state = state.copyWith(isSubmitting: false, error: null);
      return inviteUrl;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error.toString());
      }
      rethrow;
    }
  }

  Future<HouseholdInvitePreview> previewInvite(String token) async {
    final trimmedToken = token.trim();
    state = state.copyWith(
      isPreviewLoading: true,
      error: null,
      invitePreview: null,
    );
    try {
      final preview = await _gateway.previewInvite(trimmedToken);
      if (!mounted) return preview;
      state = state.copyWith(
        isPreviewLoading: false,
        error: null,
        invitePreview: preview,
      );
      return preview;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          isPreviewLoading: false,
          error: error.toString(),
          invitePreview: null,
        );
      }
      rethrow;
    }
  }

  Future<void> refreshPendingInvites({String? excludeInviteId}) async {
    if (!_gateway.isAuthenticated) {
      state = state.copyWith(
        isPendingInvitesLoading: false,
        pendingInvitePreviews: const [],
      );
      return;
    }

    state = state.copyWith(isPendingInvitesLoading: true, error: null);
    try {
      final pendingInvites = await _gateway.loadPendingInvites();
      final visibleInvites = excludeInviteId == null
          ? pendingInvites
          : pendingInvites
                .where((invite) => invite.inviteId != excludeInviteId)
                .toList(growable: false);
      if (!mounted) return;
      state = state.copyWith(
        isPendingInvitesLoading: false,
        error: null,
        pendingInvitePreviews: List.unmodifiable(visibleInvites),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isPendingInvitesLoading: false,
        error: error.toString(),
      );
    }
  }

  Future<void> acceptInvite(String token) async {
    final trimmedToken = token.trim();
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final acceptedInviteId = state.invitePreview?.inviteId;
      await _gateway.acceptInvite(trimmedToken);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final selectedId = _selectedHouseholdIdAfterJoin(
        households,
        preferredHouseholdId: state.invitePreview?.householdId,
      );
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        pendingInvitePreviews: List.unmodifiable(
          isAuthenticated
              ? state.pendingInvitePreviews.where(
                  (invite) => invite.inviteId != acceptedInviteId,
                )
              : const <HouseholdInvitePreview>[],
        ),
        invitePreview: null,
      );
      if (isAuthenticated) {
        await refreshPendingInvites(excludeInviteId: acceptedInviteId);
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<void> acceptInviteById(String inviteId) async {
    final trimmedInviteId = inviteId.trim();
    if (trimmedInviteId.isEmpty) {
      state = state.copyWith(error: '邀请不存在');
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      String? pendingInviteHouseholdId;
      for (final invite in state.pendingInvitePreviews) {
        if (invite.inviteId == trimmedInviteId) {
          pendingInviteHouseholdId = invite.householdId;
          break;
        }
      }
      await _gateway.acceptInviteById(trimmedInviteId);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final selectedId = _selectedHouseholdIdAfterJoin(
        households,
        preferredHouseholdId: pendingInviteHouseholdId,
      );
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        pendingInvitePreviews: List.unmodifiable(
          isAuthenticated
              ? state.pendingInvitePreviews.where(
                  (invite) => invite.inviteId != trimmedInviteId,
                )
              : const <HouseholdInvitePreview>[],
        ),
        invitePreview: null,
      );
      if (isAuthenticated) {
        await refreshPendingInvites(excludeInviteId: trimmedInviteId);
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<void> removeMember(String householdId, String targetUserId) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.removeMember(
        householdId: householdId,
        userId: targetUserId,
      );
      final members = await _gateway.loadHouseholdMembers(householdId);
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        householdMembers: List.unmodifiable(members),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<void> revokeInvite(String householdId, String inviteId) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.revokeInvite(inviteId);
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: null);
      await refreshOwnerPendingInvites(householdId);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<bool> dissolveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) {
      state = state.copyWith(error: '家庭不存在');
      return false;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.dissolveHousehold(trimmedHouseholdId);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final selectedId = _selectedHouseholdIdAfterRemoval(
        households,
        removedHouseholdId: trimmedHouseholdId,
      );
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted) return false;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: isAuthenticated,
        error: null,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        currentUserId: _gateway.currentUserId ?? '',
        ownerPendingInvites: const [],
        pendingInvitePreviews: isAuthenticated
            ? state.pendingInvitePreviews
            : const <HouseholdInvitePreview>[],
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
      }
      return true;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error.toString());
      }
      return false;
    }
  }

  Future<bool> leaveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) {
      state = state.copyWith(error: '家庭不存在');
      return false;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.leaveHousehold(trimmedHouseholdId);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final selectedId = _selectedHouseholdIdAfterRemoval(
        households,
        removedHouseholdId: trimmedHouseholdId,
      );
      final members = isAuthenticated
          ? await _loadMembersForSelectedHousehold(households, selectedId)
          : const <HouseholdMember>[];
      if (!mounted) return false;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: isAuthenticated,
        error: null,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        selectedHouseholdId: selectedId,
        currentUserId: _gateway.currentUserId ?? '',
        ownerPendingInvites: const [],
        pendingInvitePreviews: isAuthenticated
            ? state.pendingInvitePreviews
            : const <HouseholdInvitePreview>[],
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
      }
      return true;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error.toString());
      }
      return false;
    }
  }

  Future<void> refreshOwnerPendingInvites(String householdId) async {
    if (!_gateway.isAuthenticated) {
      state = state.copyWith(ownerPendingInvites: const []);
      return;
    }

    try {
      final invites = await _gateway.fetchOwnerPendingInvites(householdId);
      if (!mounted) return;
      state = state.copyWith(ownerPendingInvites: List.unmodifiable(invites));
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> switchHousehold(String householdId) async {
    final previousSelectedId = state.selectedHouseholdId;
    state = state.copyWith(
      isLoading: true,
      error: null,
      selectedHouseholdId: householdId,
    );
    try {
      final members = await _gateway.loadHouseholdMembers(householdId);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: null,
        householdMembers: List.unmodifiable(members),
      );
      await refreshOwnerPendingInvites(householdId);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
        selectedHouseholdId: previousSelectedId,
      );
    }
  }

  Future<void> updateHouseholdName(String householdId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: '家庭名称不能为空');
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.updateHouseholdName(householdId, trimmed);
      final households = await _gateway.loadHouseholds();
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        households: List.unmodifiable(households),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.updateCategoryPreferences(householdId, preferences);
      final households = await _gateway.loadHouseholds();
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        households: List.unmodifiable(households),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<List<HouseholdMember>> _loadMembersForSelectedHousehold(
    List<Household> households,
    String selectedHouseholdId,
  ) {
    if (households.isEmpty) return Future.value(const []);
    final targetId =
        (selectedHouseholdId.isNotEmpty &&
            households.any((h) => h.id == selectedHouseholdId))
        ? selectedHouseholdId
        : households.first.id;
    return _gateway.loadHouseholdMembers(targetId);
  }

  String _selectedHouseholdIdAfterRemoval(
    List<Household> households, {
    required String removedHouseholdId,
  }) {
    if (households.isEmpty) return '';
    final currentSelectedId = state.selectedHouseholdId;
    if (currentSelectedId.isNotEmpty &&
        currentSelectedId != removedHouseholdId &&
        households.any((household) => household.id == currentSelectedId)) {
      return currentSelectedId;
    }
    return households.first.id;
  }

  String _selectedHouseholdIdAfterJoin(
    List<Household> households, {
    String? preferredHouseholdId,
  }) {
    if (households.isEmpty) return '';
    final preferredId = preferredHouseholdId?.trim() ?? '';
    if (preferredId.isNotEmpty &&
        households.any((household) => household.id == preferredId)) {
      return preferredId;
    }
    final currentSelectedId = state.selectedHouseholdId;
    if (currentSelectedId.isNotEmpty &&
        households.any((household) => household.id == currentSelectedId)) {
      return currentSelectedId;
    }
    return households.last.id;
  }

  void _setError(Object error) {
    if (!mounted) return;
    state = state.copyWith(
      isLoading: false,
      isPendingInvitesLoading: false,
      error: error.toString(),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final householdGatewayProvider = Provider<HouseholdGateway>((ref) {
  final client = ref.read(supabaseClientProvider);
  return SupabaseHouseholdGateway(
    client,
    ref.read(remotePantryRepositoryProvider),
    ref.read(inventoryRepoProvider),
    ref.read(shoppingRepoProvider),
    ref.read(customRecipeRepoProvider),
  );
});

final householdSessionControllerProvider =
    StateNotifierProvider<HouseholdSessionController, HouseholdSessionState>((
      ref,
    ) {
      return HouseholdSessionController(ref.read(householdGatewayProvider));
    });
