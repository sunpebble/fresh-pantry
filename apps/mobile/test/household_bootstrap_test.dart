import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';
import 'package:fresh_pantry/sync/remote_pantry_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeBootstrapGateway implements HouseholdGateway {
  final authStateController = StreamController<void>.broadcast();
  final events = <String>[];
  List<Household> Function()? readHouseholds;
  List<Household> selectedDuringUpload = const [];

  @override
  bool get isAuthenticated => true;

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<List<Household>> loadHouseholds() async => const [];

  @override
  Future<Household> createHousehold(String name) async {
    events.add('create:$name');
    return const Household(
      id: 'household_1',
      name: 'Kunish Kitchen',
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    );
  }

  @override
  Future<void> uploadInitialData(String householdId) async {
    events.add('upload:$householdId');
    selectedDuringUpload = readHouseholds?.call() ?? const [];
  }

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    return const [];
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> acceptInvite(String token) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    return const [];
  }

  @override
  Future<void> acceptInviteById(String inviteId) {
    throw UnimplementedError('Not needed by these tests.');
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

class RecordingRemotePantryRepository implements RemotePantryRepository {
  final createdHouseholds = <String>[];
  final inventoryRows = <Map<String, dynamic>>[];
  final shoppingRows = <Map<String, dynamic>>[];
  final customRecipeRows = <Map<String, dynamic>>[];

  @override
  Future<List<Household>> loadHouseholds() async => const [];

  @override
  Future<Household> createHousehold(String name) async {
    createdHouseholds.add(name);
    return Household(
      id: 'household_${createdHouseholds.length}',
      name: name,
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    );
  }

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    return const [];
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> acceptInvite(String token) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    return const [];
  }

  @override
  Future<void> acceptInviteById(String inviteId) {
    throw UnimplementedError('Not needed by these tests.');
  }

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

  @override
  Future<List<Map<String, dynamic>>> loadInventory(String householdId) async {
    return const [];
  }

  @override
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    inventoryRows.addAll(rows);
  }

  @override
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    shoppingRows.addAll(rows);
  }

  @override
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    customRecipeRows.addAll(rows);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId) {
    return const Stream.empty();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId) {
    return const Stream.empty();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId) {
    return const Stream.empty();
  }
}

void main() {
  test(
    'createHousehold uploads local data before selecting household',
    () async {
      final gateway = FakeBootstrapGateway();
      final controller = HouseholdSessionController(gateway);
      gateway.readHouseholds = () => controller.state.households;

      await controller.createHousehold(' Kunish Kitchen ');

      expect(gateway.events, ['create:Kunish Kitchen', 'upload:household_1']);
      expect(gateway.selectedDuringUpload, isEmpty);
      expect(controller.state.households.single.id, 'household_1');
      expect(controller.state.isSubmitting, isFalse);

      controller.dispose();
      await gateway.close();
    },
  );

  test('createHousehold rejects empty household names', () async {
    final gateway = FakeBootstrapGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.createHousehold('  ');

    expect(gateway.events, isEmpty);
    expect(controller.state.error, '家庭名称不能为空');
    expect(controller.state.households, isEmpty);

    controller.dispose();
    await gateway.close();
  });

  test(
    'SupabaseHouseholdGateway uploads all local bootstrap repositories',
    () async {
      final adapter = InMemoryStorageAdapter();
      final inventoryRepo = InventoryRepo(adapter)
        ..saveItems([
          const Ingredient(
            name: 'Milk',
            quantity: '1',
            unit: 'box',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        ]);
      final shoppingRepo = ShoppingRepo(adapter)
        ..saveItems([
          const ShoppingItem(
            id: 'si_1',
            name: 'Eggs',
            detail: '6 pcs',
            category: '蛋类',
          ),
        ]);
      final customRecipeRepo = CustomRecipeRepo(adapter)
        ..saveRecipes([
          const Recipe(
            id: 'recipe_1',
            name: 'Omelette',
            category: '早餐',
            difficulty: 1,
            cookingMinutes: 10,
            description: 'Quick breakfast',
            ingredients: [],
            steps: ['Cook eggs'],
          ),
        ]);
      final remoteRepository = RecordingRemotePantryRepository();
      final gateway = SupabaseHouseholdGateway(
        SupabaseClient('https://example.supabase.co', 'publishable'),
        remoteRepository,
        inventoryRepo,
        shoppingRepo,
        customRecipeRepo,
      );

      await gateway.uploadInitialData('household_1');

      expect(remoteRepository.inventoryRows.single['name'], 'Milk');
      expect(remoteRepository.shoppingRows.single['name'], 'Eggs');
      expect(remoteRepository.customRecipeRows.single['name'], 'Omelette');
    },
  );
}
