import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_config_provider.dart';
import '../backend/supabase_client_provider.dart';
import '../providers/storage_service_provider.dart';
import '../storage/custom_recipe_repo.dart';
import '../storage/inventory_repo.dart';
import '../storage/shopping_repo.dart';
import '../sync/remote_pantry_repository.dart';
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
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<void> uploadInitialData(String householdId);
  Future<String> createInvite({
    required String householdId,
    required String email,
  });
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId);
  Future<List<HouseholdInvitePreview>> loadPendingInvites();
  Future<HouseholdInvitePreview> previewInvite(String token);
  Future<void> acceptInvite(String token);
  Future<void> acceptInviteById(String inviteId);
  Future<void> removeMember(String targetUserId);
  Future<void> revokeInvite(String inviteId);
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
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
    await _remoteRepository.upsertInventory(
      householdId,
      _inventoryRepo.loadAll().map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertShopping(
      householdId,
      _shoppingRepo.loadAll().map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertCustomRecipes(
      householdId,
      _customRecipeRepo.loadAll().map((recipe) => recipe.toJson()).toList(),
    );
  }

  @override
  Future<String> createInvite({
    required String householdId,
    required String email,
  }) {
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
  Future<void> removeMember(String targetUserId) {
    return _remoteRepository.removeMember(targetUserId);
  }

  @override
  Future<void> revokeInvite(String inviteId) {
    return _remoteRepository.revokeInvite(inviteId);
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId) {
    return _remoteRepository.fetchOwnerPendingInvites(householdId);
  }
}

class HouseholdSessionState {
  const HouseholdSessionState({
    this.email = '',
    this.isLoading = true,
    this.isSubmitting = false,
    this.isPreviewLoading = false,
    this.isPendingInvitesLoading = false,
    this.isAuthenticated = false,
    this.error,
    this.households = const [],
    this.householdMembers = const [],
    this.pendingInvitePreviews = const [],
    this.invitePreview,
  });

  final String email;
  final bool isLoading;
  final bool isSubmitting;
  final bool isPreviewLoading;
  final bool isPendingInvitesLoading;
  final bool isAuthenticated;
  final String? error;
  final List<Household> households;
  final List<HouseholdMember> householdMembers;
  final List<HouseholdInvitePreview> pendingInvitePreviews;
  final HouseholdInvitePreview? invitePreview;

  HouseholdSessionState copyWith({
    String? email,
    bool? isLoading,
    bool? isSubmitting,
    bool? isPreviewLoading,
    bool? isPendingInvitesLoading,
    bool? isAuthenticated,
    Object? error = _preserveError,
    List<Household>? households,
    List<HouseholdMember>? householdMembers,
    List<HouseholdInvitePreview>? pendingInvitePreviews,
    Object? invitePreview = _preserveInvitePreview,
  }) {
    return HouseholdSessionState(
      email: email ?? this.email,
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

  Future<void> sendOtp(String email) async {
    final trimmed = email.trim();
    state = state.copyWith(email: trimmed, isSubmitting: true, error: null);
    try {
      await _gateway.sendOtp(trimmed);
      if (!mounted) return;
      state = state.copyWith(email: trimmed, isSubmitting: false, error: null);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        email: trimmed,
        isSubmitting: false,
        error: error.toString(),
      );
    }
  }

  Future<void> refreshHouseholds() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final members = isAuthenticated
          ? await _loadMembersForPrimaryHousehold(households)
          : const <HouseholdMember>[];
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        pendingInvitePreviews: isAuthenticated
            ? state.pendingInvitePreviews
            : const <HouseholdInvitePreview>[],
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
      }
    } catch (error) {
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
      final members = await _loadMembersForPrimaryHousehold([household]);
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: true,
        error: null,
        households: List.unmodifiable([household]),
        householdMembers: List.unmodifiable(members),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<String> createInvite(String householdId, String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      final error = ArgumentError.value(
        email,
        'email',
        'Invite email cannot be empty',
      );
      state = state.copyWith(error: error.toString());
      throw error;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final inviteUrl = await _gateway.createInvite(
        householdId: householdId,
        email: trimmedEmail,
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
      await _gateway.acceptInvite(trimmedToken);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final members = isAuthenticated
          ? await _loadMembersForPrimaryHousehold(households)
          : const <HouseholdMember>[];
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
        pendingInvitePreviews: isAuthenticated
            ? state.pendingInvitePreviews
            : const <HouseholdInvitePreview>[],
        invitePreview: null,
      );
      if (isAuthenticated) {
        await refreshPendingInvites();
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
      await _gateway.acceptInviteById(trimmedInviteId);
      final households = await _gateway.loadHouseholds();
      final isAuthenticated = _gateway.isAuthenticated;
      final members = isAuthenticated
          ? await _loadMembersForPrimaryHousehold(households)
          : const <HouseholdMember>[];
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        isAuthenticated: isAuthenticated,
        households: List.unmodifiable(households),
        householdMembers: List.unmodifiable(members),
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

  Future<List<HouseholdMember>> _loadMembersForPrimaryHousehold(
    List<Household> households,
  ) {
    if (households.isEmpty) return Future.value(const []);
    return _gateway.loadHouseholdMembers(households.first.id);
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
  final backendConfig = ref.read(backendConfigProvider);
  return SupabaseHouseholdGateway(
    client,
    SupabaseRemotePantryRepository(
      client,
      apiBaseUrl: backendConfig.apiBaseUrl,
    ),
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
