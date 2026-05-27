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
import 'household_models.dart';

const supabaseAuthRedirectUrl = 'com.kunish.freshpantry://signin-callback/';
const _preserveError = Object();

abstract class HouseholdGateway {
  Stream<void> get authStateChanges;

  Future<void> sendOtp(String email);
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<void> uploadInitialData(String householdId);
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
      emailRedirectTo: kIsWeb ? null : supabaseAuthRedirectUrl,
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
}

class HouseholdSessionState {
  const HouseholdSessionState({
    this.email = '',
    this.isSubmitting = false,
    this.error,
    this.households = const [],
  });

  final String email;
  final bool isSubmitting;
  final String? error;
  final List<Household> households;

  HouseholdSessionState copyWith({
    String? email,
    bool? isSubmitting,
    Object? error = _preserveError,
    List<Household>? households,
  }) {
    return HouseholdSessionState(
      email: email ?? this.email,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _preserveError) ? this.error : error as String?,
      households: households ?? this.households,
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
    try {
      final households = await _gateway.loadHouseholds();
      if (!mounted) return;
      state = state.copyWith(
        error: null,
        households: List.unmodifiable(households),
      );
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
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        households: List.unmodifiable([household]),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  void _setError(Object error) {
    if (!mounted) return;
    state = state.copyWith(error: error.toString());
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
    SupabaseRemotePantryRepository(client),
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
