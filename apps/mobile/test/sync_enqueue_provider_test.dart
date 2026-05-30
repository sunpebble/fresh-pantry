import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/proposal.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart' show AppDatabase;
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

import 'support/test_database.dart';

void main() {
  test('shopping toggle enqueues sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final shoppingRepo = ShoppingRepo(db)
      ..hydrate(const [
        ShoppingItem(
          id: 'item_1',
          name: 'Rice',
          detail: '',
          category: '主食',
          remoteVersion: 7,
        ),
      ]);
    final container = _container(
      database: db,
      outbox: outbox,
      shoppingRepo: shoppingRepo,
    );
    addTearDown(container.dispose);

    await container.read(shoppingProvider.notifier).toggleCheck('item_1');

    final operation = outbox.loadPending().single;
    expect(operation.householdId, 'household_1');
    expect(operation.entityType, SyncEntityType.shoppingItem);
    expect(operation.entityId, 'item_1');
    expect(operation.operation, SyncOperationType.toggleChecked);
    expect(operation.patch, {'isChecked': true});
    expect(operation.baseVersion, 7);
    expect(operation.clientId, 'client_1');
  });

  test('inventory add enqueues create sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final container = _container(database: db, outbox: outbox);
    addTearDown(container.dispose);

    await container
        .read(inventoryProvider.notifier)
        .add(
          const Ingredient(
            id: 'ingredient_1',
            name: 'Milk',
            quantity: '1',
            unit: 'box',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
          ),
        );

    final operation = outbox.loadPending().single;
    expect(operation.entityType, SyncEntityType.inventoryItem);
    expect(operation.entityId, matches(_uuidPattern));
    expect(operation.operation, SyncOperationType.create);
    expect(operation.patch, containsPair('name', 'Milk'));
    expect(operation.patch, containsPair('id', operation.entityId));
  });

  test('inventory intake new row enqueues create sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final container = _container(database: db, outbox: outbox);
    addTearDown(container.dispose);

    await container.read(inventoryProvider.notifier).applyIntakeProposals([
      IntakeProposal(
        id: 'proposal_1',
        name: '西瓜',
        quantity: '1',
        unit: '个',
        category: FoodCategories.freshProduce,
        storage: IconType.fridge,
        shelfLifeDays: 7,
      ),
    ]);

    final operation = outbox.loadPending().single;
    expect(operation.entityType, SyncEntityType.inventoryItem);
    expect(operation.entityId, matches(_uuidPattern));
    expect(operation.operation, SyncOperationType.create);
    expect(operation.patch, containsPair('name', '西瓜'));
    expect(operation.patch, containsPair('id', operation.entityId));
  });

  test('inventory intake merge enqueues intake sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final inventoryRepo = InventoryRepo(db)
      ..hydrate(const [
        Ingredient(
          id: _inventoryId,
          name: '米',
          quantity: '1',
          unit: 'kg',
          imageUrl: '',
          freshnessPercent: 1,
          state: FreshnessState.fresh,
          category: FoodCategories.other,
          storage: IconType.pantry,
          remoteVersion: 4,
        ),
      ]);
    final container = _container(
      database: db,
      outbox: outbox,
      inventoryRepo: inventoryRepo,
    );
    addTearDown(container.dispose);

    await container.read(inventoryProvider.notifier).applyIntakeProposals([
      IntakeProposal(
        id: 'proposal_2',
        name: '米',
        quantity: '2',
        unit: 'kg',
        category: FoodCategories.other,
        storage: IconType.pantry,
        shelfLifeDays: null,
        action: IntakeAction.mergeInto,
        mergeTargetId: '0',
      ),
    ]);

    final operation = outbox.loadPending().single;
    expect(operation.entityId, _inventoryId);
    expect(operation.operation, SyncOperationType.intake);
    expect(operation.patch, containsPair('quantity', '3'));
    expect(operation.baseVersion, 4);
  });

  test('inventory deduction enqueues deduction sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final inventoryRepo = InventoryRepo(db)
      ..hydrate(const [
        Ingredient(
          id: _inventoryId,
          name: '葱',
          quantity: '5',
          unit: '个',
          imageUrl: '',
          freshnessPercent: 1,
          state: FreshnessState.fresh,
          remoteVersion: 2,
        ),
      ]);
    final container = _container(
      database: db,
      outbox: outbox,
      inventoryRepo: inventoryRepo,
    );
    addTearDown(container.dispose);

    await container.read(inventoryProvider.notifier).applyDeductionProposals([
      DeductionProposal(
        id: 'deduct_1',
        recipeIngredientName: '葱',
        requiredQty: '2个',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '葱 5 个'),
        ],
        chosenIndex: 0,
        deductAmount: '2',
      ),
    ]);

    final operation = outbox.loadPending().single;
    expect(operation.entityId, _inventoryId);
    expect(operation.operation, SyncOperationType.deduction);
    expect(operation.patch, containsPair('quantity', '3'));
    expect(operation.baseVersion, 2);
  });

  test('inventory deduction removal enqueues delete sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final inventoryRepo = InventoryRepo(db)
      ..hydrate(const [
        Ingredient(
          id: _inventoryId,
          name: '蒜',
          quantity: '1',
          unit: '个',
          imageUrl: '',
          freshnessPercent: 1,
          state: FreshnessState.fresh,
          remoteVersion: 6,
        ),
      ]);
    final container = _container(
      database: db,
      outbox: outbox,
      inventoryRepo: inventoryRepo,
    );
    addTearDown(container.dispose);

    await container.read(inventoryProvider.notifier).applyDeductionProposals([
      DeductionProposal(
        id: 'deduct_2',
        recipeIngredientName: '蒜',
        requiredQty: '1个',
        candidates: const [
          DeductionCandidate(inventoryRowIndex: 0, displayLabel: '蒜 1 个'),
        ],
        chosenIndex: 0,
        deductAmount: '1',
      ),
    ]);

    final operation = outbox.loadPending().single;
    expect(operation.entityId, _inventoryId);
    expect(operation.operation, SyncOperationType.delete);
    expect(operation.patch['deletedAt'], isA<String>());
    expect(operation.baseVersion, 6);
  });

  test('custom recipe add enqueues create sync operation', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final container = _container(database: db, outbox: outbox);
    addTearDown(container.dispose);

    await container
        .read(customRecipesProvider.notifier)
        .add(
          const Recipe(
            id: 'recipe_1',
            name: 'Tomato Pasta',
            category: '晚餐',
            difficulty: 2,
            cookingMinutes: 20,
            description: '',
            ingredients: [],
            steps: [],
          ),
        );

    final operation = outbox.loadPending().single;
    expect(operation.entityType, SyncEntityType.customRecipe);
    expect(operation.entityId, matches(_uuidPattern));
    expect(operation.operation, SyncOperationType.create);
    expect(operation.patch, containsPair('name', 'Tomato Pasta'));
    expect(operation.patch, containsPair('id', operation.entityId));
  });

  test('local-only (no household) mutation does not enqueue', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final outbox = SyncOutboxRepo(db);
    final container = _container(
      database: db,
      outbox: outbox,
      householdId: '',
    );
    addTearDown(container.dispose);

    await container.read(inventoryProvider.notifier).add(
          const Ingredient(
            name: 'Rice',
            quantity: '1',
            unit: 'kg',
            imageUrl: '',
            freshnessPercent: 1,
            state: FreshnessState.fresh,
            category: FoodCategories.other,
          ),
        );

    // No household to sync to: skipping is the correct local-first behaviour,
    // so the outbox stays empty rather than accumulating un-syncable ops.
    expect(outbox.loadPending(), isEmpty);
    expect(container.read(inventoryProvider).single.name, 'Rice');
  });
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
const _inventoryId = '00000000-0000-4000-8000-000000000001';

ProviderContainer _container({
  required AppDatabase database,
  required SyncOutboxRepo outbox,
  InventoryRepo? inventoryRepo,
  ShoppingRepo? shoppingRepo,
  String householdId = 'household_1',
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      inventoryRepoProvider.overrideWithValue(
        inventoryRepo ?? InventoryRepo(database),
      ),
      shoppingRepoProvider.overrideWithValue(
        shoppingRepo ?? ShoppingRepo(database),
      ),
      customRecipeRepoProvider.overrideWithValue(CustomRecipeRepo(database)),
      syncOutboxRepoProvider.overrideWithValue(outbox),
      selectedHouseholdIdProvider.overrideWithValue(householdId),
      syncClientIdProvider.overrideWithValue('client_1'),
      syncPushPendingProvider.overrideWithValue(() async {}),
    ],
  );
}
