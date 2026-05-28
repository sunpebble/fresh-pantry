# Household Management Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add member removal, invite revocation, and multi-household switching to the existing household management UI.

**Architecture:** Extend the existing `HouseholdSection` widget with new callbacks and state. Add 3 new Supabase RPCs (remove member, revoke invite, list owner pending invites). Extend `HouseholdSessionController` with new actions. Update `AuthGateScreen` to track selected household ID from the controller state.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase (Postgres RPCs, RLS), flutter_test

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `supabase/migrations/20260528100000_household_management.sql` | Create | 3 new RPCs: `remove_household_member`, `revoke_household_invite`, `list_owner_pending_invites` |
| `supabase/tests/family_sync_rls.sql` | Modify | Add RLS assertions for new RPCs |
| `apps/mobile/lib/household/household_models.dart` | Modify | Add `OwnerPendingInvite` model |
| `apps/mobile/lib/sync/remote_pantry_repository.dart` | Modify | Add `removeMember`, `revokeInvite`, `fetchOwnerPendingInvites` |
| `apps/mobile/lib/household/household_session_controller.dart` | Modify | Add gateway methods, state fields, controller actions |
| `apps/mobile/lib/widgets/settings/household_section.dart` | Modify | Add member removal, pending invites section, household switcher |
| `apps/mobile/lib/screens/settings_screen.dart` | Modify | Wire new callbacks to `HouseholdSection` |
| `apps/mobile/lib/screens/auth_gate_screen.dart` | Modify | Use controller's `selectedHouseholdId` for provider override |
| `apps/mobile/test/helpers/household_gateway_stub.dart` | Modify | Add stub implementations for new methods |
| `apps/mobile/test/household_session_controller_test.dart` | Modify | Add tests for `removeMember`, `revokeInvite`, `switchHousehold` |
| `apps/mobile/test/household_section_test.dart` | Modify | Add widget tests for new UI features |

---

### Task 1: SQL Migration — New RPCs

**Files:**
- Create: `supabase/migrations/20260528100000_household_management.sql`
- Modify: `supabase/tests/family_sync_rls.sql`

- [ ] **Step 1: Create the migration file with 3 RPCs**

```sql
-- remove_household_member: owner removes a member from their household
create or replace function public.remove_household_member(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_caller_id uuid := (select auth.uid());
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if target_user_id = v_caller_id then
    raise exception 'Cannot remove yourself' using errcode = 'P0001';
  end if;

  select hm.household_id into v_household_id
  from public.household_members hm
  where hm.user_id = target_user_id
    and hm.role = 'member'
    and exists (
      select 1 from public.household_members o
      where o.household_id = hm.household_id
        and o.user_id = v_caller_id
        and o.role = 'owner'
    );

  if v_household_id is null then
    raise exception 'Not authorized or target is not a member' using errcode = '42501';
  end if;

  delete from public.household_members
  where household_id = v_household_id and user_id = target_user_id;
end;
$$;

revoke all on function public.remove_household_member(uuid) from public;
revoke all on function public.remove_household_member(uuid) from anon;
grant execute on function public.remove_household_member(uuid) to authenticated;

-- revoke_household_invite: owner revokes a pending invite
create or replace function public.revoke_household_invite(target_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_caller_id uuid := (select auth.uid());
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select hi.household_id into v_household_id
  from public.household_invites hi
  where hi.id = target_invite_id
    and hi.status = 'pending'
    and exists (
      select 1 from public.household_members o
      where o.household_id = hi.household_id
        and o.user_id = v_caller_id
        and o.role = 'owner'
    );

  if v_household_id is null then
    raise exception 'Not authorized or invite not found' using errcode = '42501';
  end if;

  update public.household_invites
  set status = 'revoked'
  where id = target_invite_id;
end;
$$;

revoke all on function public.revoke_household_invite(uuid) from public;
revoke all on function public.revoke_household_invite(uuid) from anon;
grant execute on function public.revoke_household_invite(uuid) to authenticated;

-- list_owner_pending_invites: owner lists pending invites for a household
create or replace function public.list_owner_pending_invites(target_household_id uuid)
returns table (
  id uuid,
  email text,
  expires_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := (select auth.uid());
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.household_members o
    where o.household_id = target_household_id
      and o.user_id = v_caller_id
      and o.role = 'owner'
  ) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select hi.id, hi.email, hi.expires_at, hi.created_at
  from public.household_invites hi
  where hi.household_id = target_household_id
    and hi.status = 'pending'
  order by hi.created_at desc;
end;
$$;

revoke all on function public.list_owner_pending_invites(uuid) from public;
revoke all on function public.list_owner_pending_invites(uuid) from anon;
grant execute on function public.list_owner_pending_invites(uuid) to authenticated;
```

- [ ] **Step 2: Add RLS test assertions to `supabase/tests/family_sync_rls.sql`**

Read the existing file first to understand the test pattern (it uses `do $$ ... $$` blocks with `assert` statements). Append new assertion blocks following the same pattern. The assertions to add:

1. **remove_household_member — owner can remove member**: Insert a household, owner + member, call `remove_household_member(member_user_id)` as owner, assert member row is deleted.
2. **remove_household_member — member cannot remove**: Call as a non-owner member, assert exception `'Not authorized'`.
3. **remove_household_member — cannot remove self**: Call with own user_id, assert exception `'Cannot remove yourself'`.
4. **revoke_household_invite — owner can revoke**: Insert household + owner + pending invite, call `revoke_household_invite(invite_id)` as owner, assert invite status = `'revoked'`.
5. **revoke_household_invite — member cannot revoke**: Call as non-owner, assert exception `'Not authorized'`.
6. **revoke_household_invite — cannot revoke non-pending**: Insert accepted invite, call revoke, assert exception.
7. **list_owner_pending_invites — owner sees pending**: Insert household + owner + 2 pending invites, call as owner, assert returns 2 rows.
8. **list_owner_pending_invites — member gets exception**: Call as non-owner member, assert exception `'Not authorized'`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260528100000_household_management.sql supabase/tests/family_sync_rls.sql
git commit -m "feat(supabase): add remove_member, revoke_invite, list_owner_pending_invites RPCs"
```

---

### Task 2: PendingInvite Model

**Files:**
- Modify: `apps/mobile/lib/household/household_models.dart`

- [ ] **Step 1: Add `OwnerPendingInvite` model**

Append to `apps/mobile/lib/household/household_models.dart`:

```dart
class OwnerPendingInvite {
  const OwnerPendingInvite({
    required this.id,
    required this.email,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String email;
  final DateTime expiresAt;
  final DateTime createdAt;

  factory OwnerPendingInvite.fromJson(Map<String, dynamic> json) {
    return OwnerPendingInvite(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 2: Run analyze to verify**

Run: `cd apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add apps/mobile/lib/household/household_models.dart
git commit -m "feat: add OwnerPendingInvite model"
```

---

### Task 3: RemotePantryRepository — New Methods

**Files:**
- Modify: `apps/mobile/lib/sync/remote_pantry_repository.dart`

- [ ] **Step 1: Add 3 new methods to the abstract class**

In the `RemotePantryRepository` abstract class, add after `acceptInviteById`:

```dart
Future<void> removeMember(String targetUserId);
Future<void> revokeInvite(String inviteId);
Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
```

- [ ] **Step 2: Add implementations to `SupabaseRemotePantryRepository`**

Add after the `acceptInviteById` method:

```dart
@override
Future<void> removeMember(String targetUserId) async {
  final trimmedUserId = targetUserId.trim();
  if (!_isUuid(trimmedUserId)) {
    throw ArgumentError.value(targetUserId, 'targetUserId', 'Invalid user id');
  }
  if (_client.auth.currentUser == null) {
    throw StateError('Cannot remove member without a signed-in user.');
  }

  await _client.rpc(
    'remove_household_member',
    params: {'target_user_id': trimmedUserId},
  );
}

@override
Future<void> revokeInvite(String inviteId) async {
  final trimmedInviteId = inviteId.trim();
  if (!_isUuid(trimmedInviteId)) {
    throw ArgumentError.value(inviteId, 'inviteId', 'Invalid invite id');
  }
  if (_client.auth.currentUser == null) {
    throw StateError('Cannot revoke invite without a signed-in user.');
  }

  await _client.rpc(
    'revoke_household_invite',
    params: {'target_invite_id': trimmedInviteId},
  );
}

@override
Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId) async {
  final trimmedHouseholdId = householdId.trim();
  if (trimmedHouseholdId.isEmpty) return const [];
  if (_client.auth.currentUser == null) {
    throw StateError('Cannot list owner pending invites without a signed-in user.');
  }

  final rows = await _client.rpc(
    'list_owner_pending_invites',
    params: {'target_household_id': trimmedHouseholdId},
  );
  if (rows is! List) return const [];

  return rows
      .whereType<Map>()
      .map((row) => OwnerPendingInvite.fromJson(Map<String, dynamic>.from(row)))
      .toList(growable: false);
}
```

- [ ] **Step 3: Run analyze to verify**

Run: `cd apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/sync/remote_pantry_repository.dart
git commit -m "feat: add removeMember, revokeInvite, fetchOwnerPendingInvites to RemotePantryRepository"
```

---

### Task 4: HouseholdGateway — Interface + Implementation

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`

- [ ] **Step 1: Add `currentUserId` getter and 3 new methods to `HouseholdGateway` abstract class**

Add at the top of the abstract class (after `isAuthenticated`):

```dart
String? get currentUserId;
```

After `acceptInviteById`:

```dart
Future<void> removeMember(String targetUserId);
Future<void> revokeInvite(String inviteId);
Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
```

- [ ] **Step 2: Add implementations to `SupabaseHouseholdGateway`**

Add after `isAuthenticated`:

```dart
@override
String? get currentUserId => _client.auth.currentUser?.id;
```

After `acceptInviteById`:

```dart
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
```

- [ ] **Step 3: Run analyze to verify**

Run: `cd apps/mobile && flutter analyze`
Expected: Errors in test stubs (expected — fixed in Task 5)

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/household/household_session_controller.dart
git commit -m "feat: add removeMember, revokeInvite, fetchOwnerPendingInvites to HouseholdGateway"
```

---

### Task 5: Update Test Doubles

**Files:**
- Modify: `apps/mobile/test/helpers/household_gateway_stub.dart`
- Modify: `apps/mobile/test/household_session_controller_test.dart` (the `FakeHouseholdGateway` inside)

- [ ] **Step 1: Update `HouseholdGatewayStub`**

Add `currentUserId` getter and new fields/methods to `HouseholdGatewayStub`:

```dart
@override
String? get currentUserId => 'owner_1';

var removedUserId = '';
var revokedInviteId = '';
final ownerPendingInvites = <OwnerPendingInvite>[];

@override
Future<void> removeMember(String targetUserId) async {
  removedUserId = targetUserId;
}

@override
Future<void> revokeInvite(String inviteId) async {
  revokedInviteId = inviteId;
}

@override
Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId) async {
  return ownerPendingInvites;
}
```

- [ ] **Step 2: Update `FakeHouseholdGateway` in `household_session_controller_test.dart`**

Add `currentUserId` getter and new fields/methods:

```dart
@override
String? get currentUserId => 'owner_1';

var removedUserId = '';
var revokedInviteId = '';
final ownerPendingInvites = <OwnerPendingInvite>[];
Object? removeMemberError;
Object? revokeInviteError;

@override
Future<void> removeMember(String targetUserId) async {
  if (removeMemberError != null) throw removeMemberError!;
  removedUserId = targetUserId;
}

@override
Future<void> revokeInvite(String inviteId) async {
  if (revokeInviteError != null) throw revokeInviteError!;
  revokedInviteId = inviteId;
}

@override
Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId) async {
  return ownerPendingInvites;
}
```

- [ ] **Step 3: Run analyze to verify all doubles compile**

Run: `cd apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/test/helpers/household_gateway_stub.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "test: update household gateway test doubles for new methods"
```

---

### Task 6: HouseholdSessionController — `removeMember` Action

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Modify: `apps/mobile/test/household_session_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `household_session_controller_test.dart` inside `main()`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: FAIL — `removeMember` method not found on `HouseholdSessionController`

- [ ] **Step 3: Add `removeMember` to `HouseholdSessionController`**

Add after `acceptInviteById` method:

```dart
Future<void> removeMember(String householdId, String targetUserId) async {
  state = state.copyWith(isSubmitting: true, error: null);
  try {
    await _gateway.removeMember(targetUserId);
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/household/household_session_controller.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "feat: add removeMember action to HouseholdSessionController"
```

---

### Task 7: HouseholdSessionController — `revokeInvite` Action

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Modify: `apps/mobile/test/household_session_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `household_session_controller_test.dart` inside `main()`:

```dart
test('revokeInvite calls gateway and refreshes owner pending invites', () async {
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
});

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: FAIL — `revokeInvite` method not found

- [ ] **Step 3: Add `ownerPendingInvites` to `HouseholdSessionState`**

Add field to `HouseholdSessionState`:

```dart
final List<OwnerPendingInvite> ownerPendingInvites;
```

Add to constructor default: `this.ownerPendingInvites = const []`

Add to `copyWith`:

```dart
List<OwnerPendingInvite>? ownerPendingInvites,
```

And in the body: `ownerPendingInvites: ownerPendingInvites ?? this.ownerPendingInvites,`

- [ ] **Step 4: Add `revokeInvite` and `refreshOwnerPendingInvites` to `HouseholdSessionController`**

```dart
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

Future<void> refreshOwnerPendingInvites(String householdId) async {
  try {
    final invites = await _gateway.fetchOwnerPendingInvites(householdId);
    if (!mounted) return;
    state = state.copyWith(
      ownerPendingInvites: List.unmodifiable(invites),
    );
  } catch (error) {
    if (!mounted) return;
    state = state.copyWith(error: error.toString());
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/household/household_session_controller.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "feat: add revokeInvite action and ownerPendingInvites state"
```

---

### Task 8: HouseholdSessionController — `switchHousehold` Action

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Modify: `apps/mobile/test/household_session_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `household_session_controller_test.dart` inside `main()`:

```dart
test('switchHousehold updates selectedHouseholdId and reloads members', () async {
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
  expect(
    controller.state.householdMembers.map((m) => m.email),
    ['owner@example.com', 'colleague@example.com'],
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: FAIL — `selectedHouseholdId` and `switchHousehold` not found

- [ ] **Step 3: Add `selectedHouseholdId` to `HouseholdSessionState`**

Add field:

```dart
final String selectedHouseholdId;
```

Constructor default: `this.selectedHouseholdId = ''`

`copyWith` parameter: `String? selectedHouseholdId,`

Body: `selectedHouseholdId: selectedHouseholdId ?? this.selectedHouseholdId,`

- [ ] **Step 4: Add `switchHousehold` to `HouseholdSessionController`**

```dart
Future<void> switchHousehold(String householdId) async {
  state = state.copyWith(isLoading: true, error: null, selectedHouseholdId: householdId);
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
    state = state.copyWith(isLoading: false, error: error.toString());
  }
}
```

- [ ] **Step 5: Update `refreshHouseholds` to set `selectedHouseholdId`**

In `refreshHouseholds()`, change the state update to include `selectedHouseholdId`. If the current `selectedHouseholdId` is empty or no longer in the list, default to `households.first.id`:

```dart
final currentSelectedId = state.selectedHouseholdId;
final selectedId = (currentSelectedId.isNotEmpty &&
        households.any((h) => h.id == currentSelectedId))
    ? currentSelectedId
    : (households.isEmpty ? '' : households.first.id);
```

Add `selectedHouseholdId: selectedId` to the `state.copyWith(...)` call in `refreshHouseholds`.

Also update `_loadMembersForPrimaryHousehold` to accept a `selectedHouseholdId` parameter instead of always using `households.first`:

```dart
Future<List<HouseholdMember>> _loadMembersForSelectedHousehold(
  List<Household> households,
  String selectedHouseholdId,
) {
  if (households.isEmpty) return Future.value(const []);
  final targetId = (selectedHouseholdId.isNotEmpty &&
          households.any((h) => h.id == selectedHouseholdId))
      ? selectedHouseholdId
      : households.first.id;
  return _gateway.loadHouseholdMembers(targetId);
}
```

Update all call sites of `_loadMembersForPrimaryHousehold` to use `_loadMembersForSelectedHouseload` with the appropriate `selectedHouseholdId`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_session_controller_test.dart`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/household/household_session_controller.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "feat: add switchHousehold action and selectedHouseholdId state"
```

---

### Task 9: HouseholdSection UI — Member Removal

**Files:**
- Modify: `apps/mobile/lib/widgets/settings/household_section.dart`
- Modify: `apps/mobile/test/household_section_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add to `household_section_test.dart`:

```dart
testWidgets('HouseholdSection shows dismissible on member rows for owner', (tester) async {
  var removedUserId = '';
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
          onRemoveMember: (userId) async {
            removedUserId = userId;
          },
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: FAIL — `isOwner`, `currentUserId`, `onRemoveMember` parameters not found

- [ ] **Step 3: Add new parameters to `HouseholdSection`**

Update the constructor:

```dart
class HouseholdSection extends StatelessWidget {
  const HouseholdSection({
    super.key,
    required this.householdName,
    required this.members,
    this.onInvite,
    this.onInviteEmail,
    this.isOwner = false,
    this.currentUserId = '',
    this.onRemoveMember,
    this.ownerPendingInvites = const [],
    this.onRevokeInvite,
    this.households = const [],
    this.selectedHouseholdId = '',
    this.onSwitchHousehold,
  });

  final String householdName;
  final List<HouseholdMember> members;
  final VoidCallback? onInvite;
  final Future<void> Function(String email)? onInviteEmail;
  final bool isOwner;
  final String currentUserId;
  final Future<void> Function(String userId)? onRemoveMember;
  final List<OwnerPendingInvite> ownerPendingInvites;
  final Future<void> Function(String inviteId)? onRevokeInvite;
  final List<Household> households;
  final String selectedHouseholdId;
  final ValueChanged<String>? onSwitchHousehold;
```

- [ ] **Step 4: Update `_MemberRow` to support dismissal**

Replace the member list rendering in `build()`. For each member, wrap in `Dismissible` if `isOwner && member.userId != currentUserId && member.role != 'owner'`:

```dart
for (final member in members)
  _buildMemberRow(context, member),
```

Add a helper method:

```dart
Widget _buildMemberRow(BuildContext context, HouseholdMember member) {
  final canRemove = isOwner &&
      member.userId != currentUserId &&
      member.role != 'owner' &&
      onRemoveMember != null;

  final row = _MemberRow(member: member);

  if (!canRemove) return row;

  return Dismissible(
    key: ValueKey('member_${member.userId}'),
    direction: DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.xl),
      color: AppColors.fkDanger,
      child: const Icon(Icons.delete_outline, color: Colors.white),
    ),
    confirmDismiss: (_) async {
      return showAppConfirmDialog(
        context,
        title: '移除成员',
        content: '确定移除 ${member.email}？',
        confirmLabel: '移除',
        isDestructive: true,
      );
    },
    onDismissed: (_) => onRemoveMember!(member.userId),
    child: row,
  );
}
```

Add import for `showAppConfirmDialog` and `OwnerPendingInvite`:

```dart
import '../../household/household_models.dart';
import '../../utils/app_dialog.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/widgets/settings/household_section.dart apps/mobile/test/household_section_test.dart
git commit -m "feat: add member removal UI to HouseholdSection"
```

---

### Task 10: HouseholdSection UI — Pending Invites Section

**Files:**
- Modify: `apps/mobile/lib/widgets/settings/household_section.dart`
- Modify: `apps/mobile/test/household_section_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add to `household_section_test.dart`:

```dart
testWidgets('HouseholdSection shows pending invites when owner has them', (tester) async {
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

testWidgets('HouseholdSection hides pending invites section when empty', (tester) async {
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: FAIL — `待处理邀请` not found

- [ ] **Step 3: Add pending invites section to `HouseholdSection.build()`**

After the member list and before the invite button, add:

```dart
if (isOwner && ownerPendingInvites.isNotEmpty) ...[
  const SizedBox(height: AppSpacing.md),
  Text(
    '待处理邀请',
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppColors.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    ),
  ),
  const SizedBox(height: AppSpacing.sm),
  for (final invite in ownerPendingInvites)
    _PendingInviteRow(
      invite: invite,
      onRevoke: onRevokeInvite != null
          ? () => onRevokeInvite!(invite.id)
          : null,
    ),
],
```

Add the `_PendingInviteRow` widget:

```dart
class _PendingInviteRow extends StatelessWidget {
  const _PendingInviteRow({required this.invite, this.onRevoke});

  final OwnerPendingInvite invite;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.mail_outline,
            color: AppColors.outline,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '待接受',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.fkDanger,
              onPressed: onRevoke,
              tooltip: '撤销邀请',
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/settings/household_section.dart apps/mobile/test/household_section_test.dart
git commit -m "feat: add pending invites section to HouseholdSection"
```

---

### Task 11: HouseholdSection UI — Household Switcher

**Files:**
- Modify: `apps/mobile/lib/widgets/settings/household_section.dart`
- Modify: `apps/mobile/test/household_section_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add to `household_section_test.dart`:

```dart
testWidgets('HouseholdSection dropdown renders all households', (tester) async {
  var switchedTo = '';
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HouseholdSection(
          householdName: 'Home',
          members: const [],
          households: const [
            Household(id: 'h1', name: 'Home', ownerId: 'o1', defaultStorageArea: 'fridge'),
            Household(id: 'h2', name: 'Office', ownerId: 'o1', defaultStorageArea: 'pantry'),
          ],
          selectedHouseholdId: 'h1',
          onSwitchHousehold: (id) {
            switchedTo = id;
          },
        ),
      ),
    ),
  );

  expect(find.byType(DropdownButton<String>), findsOneWidget);
});

testWidgets('HouseholdSection shows static name when single household', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: HouseholdSection(
          householdName: 'Solo Kitchen',
          members: [],
          households: [
            Household(id: 'h1', name: 'Solo Kitchen', ownerId: 'o1', defaultStorageArea: 'fridge'),
          ],
          selectedHouseholdId: 'h1',
        ),
      ),
    ),
  );

  expect(find.byType(DropdownButton<String>), findsNothing);
  expect(find.text('Solo Kitchen'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: FAIL — `DropdownButton` not found

- [ ] **Step 3: Replace static household name with conditional dropdown**

In `HouseholdSection.build()`, replace the household name `Row` with:

```dart
Row(
  children: [
    Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.home_rounded,
        color: AppColors.primaryContainer,
        size: 20,
      ),
    ),
    const SizedBox(width: AppSpacing.md),
    Expanded(
      child: households.length > 1 && onSwitchHousehold != null
          ? DropdownButton<String>(
              value: selectedHouseholdId.isNotEmpty &&
                      households.any((h) => h.id == selectedHouseholdId)
                  ? selectedHouseholdId
                  : households.first.id,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final h in households)
                  DropdownMenuItem(
                    value: h.id,
                    child: Text(
                      h.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSwitchHousehold!(value);
              },
            )
          : Text(
              householdName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
    ),
  ],
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/household_section_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/settings/household_section.dart apps/mobile/test/household_section_test.dart
git commit -m "feat: add household switcher dropdown to HouseholdSection"
```

---

### Task 12: Wire SettingsScreen + AuthGateScreen

**Files:**
- Modify: `apps/mobile/lib/screens/settings_screen.dart`
- Modify: `apps/mobile/lib/screens/auth_gate_screen.dart`

- [ ] **Step 1: Update `SettingsScreen` to pass new props to `HouseholdSection`**

In `SettingsScreen.build()`, update the `HouseholdSection` widget:

```dart
HouseholdSection(
  householdName: household?.name ?? '未加入家庭',
  members: household == null
      ? const []
      : householdSession.householdMembers,
  onInviteEmail: household == null
      ? null
      : (email) => _onInviteEmail(household.id, email),
  isOwner: household != null && household.ownerId == householdSession.currentUserId,
  currentUserId: householdSession.currentUserId,
  onRemoveMember: household == null
      ? null
      : (userId) => _onRemoveMember(household.id, userId),
  ownerPendingInvites: householdSession.ownerPendingInvites,
  onRevokeInvite: household == null
      ? null
      : (inviteId) => _onRevokeInvite(household.id, inviteId),
  households: householdSession.households,
  selectedHouseholdId: householdSession.selectedHouseholdId,
  onSwitchHousehold: (id) => _onSwitchHousehold(id),
),
```

The `currentUserId` comes from `HouseholdSessionState.currentUserId` (added in this step). Add to `HouseholdSessionState`:

```dart
final String currentUserId;
```

Constructor default: `this.currentUserId = ''`

`copyWith` parameter: `String? currentUserId,`

Body: `currentUserId: currentUserId ?? this.currentUserId,`

Add getter to `HouseholdGateway`:

```dart
String? get currentUserId;
```

Add to `SupabaseHouseholdGateway`:

```dart
@override
String? get currentUserId => _client.auth.currentUser?.id;
```

In `refreshHouseholds()`, set `currentUserId` in the state copy:

```dart
currentUserId: _gateway.currentUserId ?? '',
```

In `SettingsScreen`, use `householdSession.currentUserId` instead of a helper method.

Add action methods:

```dart
Future<void> _onRemoveMember(String householdId, String userId) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: '移除成员',
    content: '确定移除该成员？',
    confirmLabel: '移除',
    isDestructive: true,
  );
  if (!confirmed || !mounted) return;
  await ref
      .read(householdSessionControllerProvider.notifier)
      .removeMember(householdId, userId);
}

Future<void> _onRevokeInvite(String householdId, String inviteId) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: '撤销邀请',
    content: '确定撤销该邀请？',
    confirmLabel: '撤销',
    isDestructive: true,
  );
  if (!confirmed || !mounted) return;
  await ref
      .read(householdSessionControllerProvider.notifier)
      .revokeInvite(householdId, inviteId);
}

void _onSwitchHousehold(String householdId) {
  ref
      .read(householdSessionControllerProvider.notifier)
      .switchHousehold(householdId);
}
```

Add import for `showAppConfirmDialog`:

```dart
import '../utils/app_dialog.dart';
```

- [ ] **Step 2: Update `AuthGateScreen` to use `selectedHouseholdId`**

In `AuthGateScreen.build()`, change the provider override:

```dart
if (session.households.isNotEmpty) {
  final selectedId = session.selectedHouseholdId.isNotEmpty
      ? session.selectedHouseholdId
      : session.households.first.id;
  return ProviderScope(
    overrides: [
      selectedHouseholdIdProvider.overrideWithValue(selectedId),
    ],
    child: widget.authenticatedChild,
  );
}
```

- [ ] **Step 3: Update `HouseholdGatewayStub` and `FakeHouseholdGateway` for `currentUserId`**

Add to `HouseholdGatewayStub`:

```dart
@override
String? get currentUserId => 'owner_1';
```

Add to `FakeHouseholdGateway` in `household_session_controller_test.dart`:

```dart
@override
String? get currentUserId => 'owner_1';
```

- [ ] **Step 4: Run full test suite**

Run: `cd apps/mobile && flutter test`
Expected: All tests PASS

- [ ] **Step 5: Run analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/settings_screen.dart apps/mobile/lib/screens/auth_gate_screen.dart apps/mobile/lib/household/household_session_controller.dart apps/mobile/test/helpers/household_gateway_stub.dart apps/mobile/test/household_session_controller_test.dart
git commit -m "feat: wire household management enhancements in SettingsScreen and AuthGateScreen"
```

---

### Task 13: Final Verification

- [ ] **Step 1: Run full Flutter analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: No issues found

- [ ] **Step 2: Run full Flutter test suite**

Run: `cd apps/mobile && flutter test`
Expected: All tests PASS

- [ ] **Step 3: Run API tests**

Run: `cd apps/api && npm test`
Expected: All tests PASS

- [ ] **Step 4: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: cleanup after household management enhancement"
```
