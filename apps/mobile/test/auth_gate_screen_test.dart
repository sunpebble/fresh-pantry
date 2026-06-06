import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/invite_link_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/auth_gate_screen.dart';
import 'package:fresh_pantry/services/invite_link_service.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

import 'support/test_database.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  FakeHouseholdGateway({
    this.initialHouseholds = const [],
    this.isAuthenticated = false,
    this.loadHouseholdsCompleter,
  });

  final authStateController = StreamController<void>.broadcast();
  List<Household> initialHouseholds;
  List<HouseholdInvitePreview> pendingInvites = const [];
  Completer<List<Household>>? loadHouseholdsCompleter;
  @override
  bool isAuthenticated;
  var sentEmail = '';
  var verifiedEmail = '';
  var verifiedToken = '';
  Object? verifyOtpError;
  var createdHouseholdName = '';
  var acceptedInviteId = '';
  Object? acceptInviteError;

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {
    sentEmail = email;
  }

  @override
  Future<void> verifyEmailOtp(String email, String token) async {
    if (verifyOtpError != null) throw verifyOtpError!;
    verifiedEmail = email;
    verifiedToken = token;
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    return loadHouseholdsCompleter?.future ?? initialHouseholds;
  }

  @override
  Future<Household> createHousehold(String name) async {
    createdHouseholdName = name;
    final household = Household(
      id: 'household_1',
      name: name,
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    );
    initialHouseholds = [household];
    return household;
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  @override
  Future<String> createInvite({required String householdId, String? email}) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    return const HouseholdInvitePreview(
      householdId: 'household_2',
      householdName: 'Kunish Shared Kitchen',
      ownerEmail: 'owner@example.com',
      invitedEmail: 'member@example.com',
      memberCount: 2,
      inventoryCount: 5,
      shoppingCount: 3,
      customRecipeCount: 1,
    );
  }

  @override
  Future<void> acceptInvite(String token) async {
    if (acceptInviteError != null) throw acceptInviteError!;
    initialHouseholds = const [
      Household(
        id: 'household_2',
        name: 'Kunish Shared Kitchen',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ];
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    return const [];
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    return pendingInvites;
  }

  @override
  Future<void> acceptInviteById(String inviteId) async {
    acceptedInviteId = inviteId;
    initialHouseholds = const [
      Household(
        id: 'household_2',
        name: 'Kunish Shared Kitchen',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ];
    pendingInvites = const [];
  }

  @override
  String? get currentUserId => 'owner_1';

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> revokeInvite(String inviteId) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> dissolveHousehold(String householdId) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> leaveHousehold(String householdId) {
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

  void emitAuthStateChange() {
    authStateController.add(null);
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('resolveSupabaseAuthRedirectUrl uses the mobile deep link', () {
    expect(
      resolveSupabaseAuthRedirectUrl(isWeb: false),
      'com.kunish.freshpantry://signin-callback/',
    );
  });

  test('resolveSupabaseAuthRedirectUrl uses the current web origin', () {
    expect(
      resolveSupabaseAuthRedirectUrl(
        isWeb: true,
        webBaseUri: Uri.parse('http://localhost:61733/#/login?x=1'),
      ),
      'http://localhost:61733/',
    );
  });

  testWidgets(
    'AuthGateScreen renders email OTP form when no household is loaded',
    (tester) async {
      await tester.pumpWidget(_wrap(FakeHouseholdGateway()));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '发送验证码'), findsOneWidget);
      expect(find.text('App Shell'), findsNothing);
    },
  );

  testWidgets('AuthGateScreen sends trimmed OTP email', (tester) async {
    final gateway = FakeHouseholdGateway();
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      ' owner@example.com ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送验证码'));
    await tester.pumpAndSettle();

    expect(gateway.sentEmail, 'owner@example.com');
  });

  testWidgets('AuthGateScreen confirms the OTP email was sent', (tester) async {
    final gateway = FakeHouseholdGateway();
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'owner@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送验证码'));
    await tester.pumpAndSettle();

    expect(
      find.text('验证码已发送至 owner@example.com，请输入邮件中的验证码'),
      findsOneWidget,
    );
  });

  testWidgets('AuthGateScreen verifies the entered OTP code', (tester) async {
    final gateway = FakeHouseholdGateway();
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'owner@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送验证码'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '验证码'), ' 123456 ');
    await tester.tap(find.widgetWithText(FilledButton, '验证并登录'));
    await tester.pumpAndSettle();

    expect(gateway.verifiedEmail, 'owner@example.com');
    expect(gateway.verifiedToken, '123456');
  });

  testWidgets(
    'AuthGateScreen renders household bootstrap for signed-in users without households',
    (tester) async {
      final gateway = FakeHouseholdGateway(isAuthenticated: true);
      await tester.pumpWidget(_wrap(gateway));
      await tester.pumpAndSettle();

      expect(find.text('创建家庭配置'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '创建家庭'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
    },
  );

  testWidgets(
    'AuthGateScreen shows startup screen while signed-in session loads',
    (tester) async {
      final householdsCompleter = Completer<List<Household>>();
      final gateway = FakeHouseholdGateway(
        isAuthenticated: true,
        loadHouseholdsCompleter: householdsCompleter,
      );

      await tester.pumpWidget(_wrap(gateway));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
      expect(find.text('创建家庭配置'), findsNothing);

      householdsCompleter.complete(const [
        Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('AuthGateScreen creates first household', (tester) async {
    final gateway = FakeHouseholdGateway(isAuthenticated: true);
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '家庭名称'),
      ' Kunish Kitchen ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建家庭'));
    await tester.pumpAndSettle();

    expect(gateway.createdHouseholdName, 'Kunish Kitchen');
    expect(find.text('App Shell'), findsOneWidget);
    expect(find.text('创建家庭配置'), findsNothing);
  });

  testWidgets('AuthGateScreen previews invite before accepting it', (
    tester,
  ) async {
    final gateway = FakeHouseholdGateway(isAuthenticated: true);
    await tester.pumpWidget(_wrap(gateway, initialInviteToken: 'abcDEF123_-'));
    await tester.pumpAndSettle();

    expect(find.text('Kunish Shared Kitchen'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('5 个食材'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '接受邀请'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '接受邀请'));
    await tester.pumpAndSettle();

    expect(find.text('App Shell'), findsOneWidget);
    expect(find.text('Kunish Shared Kitchen'), findsNothing);
  });

  testWidgets(
    'AuthGateScreen shows accept errors while keeping invite overview visible',
    (tester) async {
      final gateway = FakeHouseholdGateway(isAuthenticated: true)
        ..acceptInviteError = StateError('Invite is not available');
      await tester.pumpWidget(
        _wrap(gateway, initialInviteToken: 'abcDEF123_-'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '接受邀请'));
      await tester.pumpAndSettle();

      expect(find.text('Kunish Shared Kitchen'), findsOneWidget);
      expect(find.textContaining('Invite is not available'), findsOneWidget);
      expect(find.text('App Shell'), findsNothing);
    },
  );

  testWidgets('AuthGateScreen shows pending invite reminders after login', (
    tester,
  ) async {
    final gateway = FakeHouseholdGateway(isAuthenticated: true)
      ..pendingInvites = [
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
      ];
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    expect(find.text('收到家庭邀请'), findsOneWidget);
    expect(find.text('Kunish Shared Kitchen'), findsOneWidget);
    expect(find.text('5 个食材'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '接受邀请'));
    await tester.pumpAndSettle();

    expect(gateway.acceptedInviteId, 'invite_1');
    expect(find.text('App Shell'), findsOneWidget);
    expect(find.text('收到家庭邀请'), findsNothing);
  });

  testWidgets('AuthGateScreen previews a manually entered invite url', (
    tester,
  ) async {
    final gateway = FakeHouseholdGateway(isAuthenticated: true);
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '邀请链接或邀请码'),
      'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-',
    );
    await tester.tap(find.widgetWithText(FilledButton, '查看邀请'));
    await tester.pumpAndSettle();

    expect(find.text('Kunish Shared Kitchen'), findsOneWidget);
    expect(find.text('3 个采购'), findsOneWidget);
  });

  testWidgets(
    'AuthGateScreen previews invite links received while app is open',
    (tester) async {
      final gateway = FakeHouseholdGateway(
        isAuthenticated: true,
        initialHouseholds: const [
          Household(
            id: 'household_1',
            name: 'Home',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge',
          ),
        ],
      );
      final linkSource = InMemoryInviteLinkSource();
      addTearDown(linkSource.close);

      await tester.pumpWidget(_wrap(gateway, inviteLinkSource: linkSource));
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);

      linkSource.emit('com.kunish.freshpantry://invite/abcDEF123_-');
      await tester.pumpAndSettle();

      expect(find.text('家庭邀请'), findsOneWidget);
      expect(find.text('Kunish Shared Kitchen'), findsOneWidget);
    },
  );

  testWidgets(
    'AuthGateScreen shows authenticated child after households load',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FakeHouseholdGateway(
            initialHouseholds: const [
              Household(
                id: 'household_1',
                name: 'Home',
                ownerId: 'owner_1',
                defaultStorageArea: 'fridge',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
    },
  );

  testWidgets(
    'AuthGateScreen exposes selected household id to authenticated child',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FakeHouseholdGateway(
            initialHouseholds: const [
              Household(
                id: 'household_1',
                name: 'Home',
                ownerId: 'owner_1',
                defaultStorageArea: 'fridge',
              ),
            ],
          ),
          child: Consumer(
            builder: (context, ref, _) {
              return Text(ref.watch(selectedHouseholdIdProvider));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('household_1'), findsOneWidget);
    },
  );

  testWidgets(
    'inventory mutations from the authenticated subtree sync to the active household',
    (tester) async {
      // Reproduces the production widget tree: a root ProviderScope (where the
      // global notifiers live) wrapping AuthGateScreen, which exposes the
      // selected household to its authenticated subtree. A regression guard for
      // the nested-ProviderScope override trap: an override applied only to the
      // authenticated subtree never reached the root-stored InventoryNotifier,
      // so every add/edit/delete silently no-opped (empty household) and never
      // synced — the other household members never saw it.
      final db = newTestDatabase();
      addTearDown(db.close);
      final outbox = SyncOutboxRepo(db);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            householdGatewayProvider.overrideWithValue(
              FakeHouseholdGateway(
                isAuthenticated: true,
                initialHouseholds: const [
                  Household(
                    id: 'household_1',
                    name: 'Home',
                    ownerId: 'owner_1',
                    defaultStorageArea: 'fridge',
                  ),
                ],
              ),
            ),
            appDatabaseProvider.overrideWithValue(db),
            inventoryRepoProvider.overrideWithValue(InventoryRepo(db)),
            syncOutboxRepoProvider.overrideWithValue(outbox),
            syncClientIdProvider.overrideWithValue('client_1'),
            syncPushPendingProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp(
            home: AuthGateScreen(
              authenticatedChild: const _InventoryAdderProbe(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-inventory')));
      await tester.pumpAndSettle();

      final operation = outbox.loadPending().single;
      expect(operation.householdId, 'household_1');
      expect(operation.entityType, SyncEntityType.inventoryItem);
      expect(operation.operation, SyncOperationType.create);
    },
  );

  testWidgets(
    'AuthGateScreen shows authenticated child after auth state changes',
    (tester) async {
      final gateway = FakeHouseholdGateway();
      await tester.pumpWidget(_wrap(gateway));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);

      gateway.initialHouseholds = const [
        Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      ];
      gateway.emitAuthStateChange();
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);

      await gateway.close();
    },
  );

  testWidgets('FreshPantryApp defaults to AuthGateScreen', (tester) async {
    final db = newTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
          ...testStorageOverrides(database: db),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AuthGateScreen), findsOneWidget);
    expect(find.text('登录 Fresh Pantry'), findsOneWidget);
  });
}

class _InventoryAdderProbe extends ConsumerWidget {
  const _InventoryAdderProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      key: const Key('add-inventory'),
      onPressed: () => ref.read(inventoryProvider.notifier).add(
        const Ingredient(
          name: 'Rice',
          quantity: '1',
          unit: 'kg',
          imageUrl: '',
          freshnessPercent: 1,
          state: FreshnessState.fresh,
          category: FoodCategories.other,
        ),
      ),
      child: const Text('add'),
    );
  }
}

Widget _wrap(
  FakeHouseholdGateway gateway, {
  Widget child = const Text('App Shell'),
  String? initialInviteToken,
  InviteLinkSource? inviteLinkSource,
}) {
  final db = newTestDatabase();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [
      householdGatewayProvider.overrideWithValue(gateway),
      ...testStorageOverrides(database: db),
      if (inviteLinkSource != null)
        inviteLinkSourceProvider.overrideWithValue(inviteLinkSource),
    ],
    child: MaterialApp(
      home: AuthGateScreen(
        authenticatedChild: child,
        initialInviteToken: initialInviteToken,
      ),
    ),
  );
}
