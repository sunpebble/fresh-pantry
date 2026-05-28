begin;

select plan(52);

create or replace function pg_temp.authenticate_as(user_id uuid, user_email text)
returns void
language sql
as $$
  select set_config('request.jwt.claim.sub', user_id::text, true);
  select set_config('request.jwt.claim.email', user_email, true);
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', user_id::text,
      'email', user_email,
      'role', 'authenticated'
    )::text,
    true
  );
$$;

create or replace function pg_temp.clear_auth()
returns void
language sql
as $$
  select set_config('request.jwt.claim.sub', '', true);
  select set_config('request.jwt.claim.email', '', true);
  select set_config('request.jwt.claims', '{}'::text, true);
$$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'owner@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'member@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'outsider@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

insert into public.households (id, name, owner_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Kunish Kitchen', '11111111-1111-1111-1111-111111111111')
on conflict (id) do nothing;

insert into public.household_members (household_id, user_id, role)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member')
on conflict (household_id, user_id) do nothing;

set local role authenticated;

select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'owner can read household'
);

select lives_ok(
  $$
    insert into public.inventory_items (household_id, name, quantity, unit, storage)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Milk', '1', 'box', 'fridge')
  $$,
  'owner can write inventory'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'member can read shared inventory'
);

select is(
  (
    select string_agg(email || ':' || role, ',' order by email)
    from public.list_household_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  ),
  'member@example.com:member,owner@example.com:owner',
  'member can list household members with emails'
);

select lives_ok(
  $$
    insert into public.shopping_items (household_id, name, detail, category)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Eggs', '12 count', 'Dairy')
  $$,
  'member can write shopping item'
);

select lives_ok(
  $$
    insert into public.sync_events (
      household_id,
      entity_type,
      entity_id,
      operation,
      client_id,
      created_by
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'shopping_item',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'insert',
      'member-client',
      '22222222-2222-2222-2222-222222222222'
    )
  $$,
  'member can write own sync event'
);

select pg_temp.authenticate_as('33333333-3333-3333-3333-333333333333', 'outsider@example.com');

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read household'
);

select throws_ok(
  $$ select * from public.list_household_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  '42501',
  'Household access denied',
  'non-member cannot list household members'
);

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read inventory'
);

select throws_ok(
  $$
    insert into public.inventory_items (household_id, name, quantity, unit, storage)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Butter', '1', 'pack', 'fridge')
  $$,
  '42501',
  'new row violates row-level security policy for table "inventory_items"',
  'non-member cannot write inventory'
);

select throws_ok(
  $$
    insert into public.custom_recipes (household_id, payload)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{"name":"Soup"}'::jsonb)
  $$,
  '42501',
  'new row violates row-level security policy for table "custom_recipes"',
  'non-member cannot write custom recipe'
);

select throws_ok(
  $$
    insert into public.sync_events (
      household_id,
      entity_type,
      entity_id,
      operation,
      client_id,
      created_by
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'inventory_item',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'insert',
      'outsider-client',
      '33333333-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "sync_events"',
  'non-member cannot write sync event'
);

select throws_ok(
  $$
    insert into public.household_members (household_id, user_id, role)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'owner')
  $$,
  '42501',
  'new row violates row-level security policy for table "household_members"',
  'non-owner cannot self-add as household owner'
);

select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

insert into public.household_invites (
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'outsider@example.com',
  'outsider-invite-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'outsider@example.com',
  'outsider-app-reminder-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.household_invites (
  household_id,
  email,
  token_hash,
  status,
  expires_at,
  created_by
)
values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'outsider@example.com',
    'expired-invite-token',
    'pending',
    now() - interval '1 minute',
    '11111111-1111-1111-1111-111111111111'
  ),
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'outsider@example.com',
    'revoked-invite-token',
    'revoked',
    now() + interval '7 days',
    '11111111-1111-1111-1111-111111111111'
  );

select pg_temp.clear_auth();

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  '28000',
  'Authentication required',
  'invite acceptance requires auth uid'
);

select ok(
  not has_function_privilege('anon', 'public.accept_household_invite(text)', 'execute'),
  'anon cannot execute invite acceptance rpc'
);

select ok(
  not has_function_privilege('anon', 'public.preview_household_invite(text)', 'execute'),
  'anon cannot execute invite preview rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_pending_household_invites()', 'execute'),
  'anon cannot execute pending invite list rpc'
);

select ok(
  not has_function_privilege('anon', 'public.accept_household_invite_by_id(uuid)', 'execute'),
  'anon cannot execute invite acceptance by id rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_household_members(uuid)', 'execute'),
  'anon cannot execute household member list rpc'
);

select throws_ok(
  $$ select public.preview_household_invite('outsider-invite-token') $$,
  '28000',
  'Authentication required',
  'invite preview requires auth uid'
);

select throws_ok(
  $$ select * from public.list_pending_household_invites() $$,
  '28000',
  'Authentication required',
  'pending invite list requires auth uid'
);

select throws_ok(
  $$ select public.remove_household_member('22222222-2222-2222-2222-222222222222'::uuid) $$,
  '28000',
  'Authentication required',
  'remove_household_member requires auth uid'
);

select throws_ok(
  $$ select public.revoke_household_invite('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) $$,
  '28000',
  'Authentication required',
  'revoke_household_invite requires auth uid'
);

select throws_ok(
  $$ select * from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  '28000',
  'Authentication required',
  'list_owner_pending_invites requires auth uid'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.preview_household_invite('outsider-invite-token') $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot preview invite'
);

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot accept invite'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  0::bigint,
  'wrong email cannot list pending invite reminders'
);

select throws_ok(
  $$ select public.accept_household_invite_by_id('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid) $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot accept invite by id'
);

select pg_temp.authenticate_as('33333333-3333-3333-3333-333333333333', 'outsider@example.com');

select throws_ok(
  $$ select public.preview_household_invite('expired-invite-token') $$,
  'P0001',
  'Invite is not available',
  'expired invite cannot be previewed'
);

select throws_ok(
  $$ select public.accept_household_invite('expired-invite-token') $$,
  'P0001',
  'Invite is not available',
  'expired invite cannot be accepted'
);

select throws_ok(
  $$ select public.accept_household_invite('revoked-invite-token') $$,
  'P0001',
  'Invite is not available',
  'revoked invite cannot be accepted'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  2::bigint,
  'matching invited email can list pending invite reminders'
);

select is(
  (
    select household_name || ':' || owner_email || ':' || inventory_count || ':' || shopping_count
    from public.list_pending_household_invites()
    where invite_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  ),
  'Kunish Kitchen:owner@example.com:1:1',
  'pending invite reminder includes household overview'
);

select lives_ok(
  $$ select public.accept_household_invite_by_id('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid) $$,
  'matching invited email can accept invite by id'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  1::bigint,
  'accepted invite by id is removed from pending reminders'
);

select is(
  (
    select household_name || ':' || owner_email || ':' || inventory_count || ':' || shopping_count
    from public.preview_household_invite('outsider-invite-token')
  ),
  'Kunish Kitchen:owner@example.com:1:1',
  'matching invited email can preview household overview'
);

select lives_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  'matching invited email can accept invite'
);

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  'P0001',
  'Invite is not available',
  'accepted invite cannot be replayed'
);

select is(
  (
    select count(*)
    from public.household_members
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and user_id = '33333333-3333-3333-3333-333333333333'
      and role = 'member'
  ),
  1::bigint,
  'accepted user becomes household member'
);

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'accepted user can read household'
);

-- === New RPC tests for household management enhancement ===

-- Test: anon cannot execute new RPCs
select ok(
  not has_function_privilege('anon', 'public.remove_household_member(uuid)', 'execute'),
  'anon cannot execute remove_household_member rpc'
);

select ok(
  not has_function_privilege('anon', 'public.revoke_household_invite(uuid)', 'execute'),
  'anon cannot execute revoke_household_invite rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_owner_pending_invites(uuid)', 'execute'),
  'anon cannot execute list_owner_pending_invites rpc'
);

-- Test: owner can remove a member (outsider was added as member earlier)
select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

select lives_ok(
  $$ select public.remove_household_member('33333333-3333-3333-3333-333333333333'::uuid) $$,
  'owner can remove a member'
);

select is(
  (
    select count(*)
    from public.household_members
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'removed member is no longer in household'
);

-- Test: owner cannot remove self
select throws_ok(
  $$ select public.remove_household_member('11111111-1111-1111-1111-111111111111'::uuid) $$,
  'P0001',
  'Cannot remove yourself',
  'owner cannot remove self'
);

-- Test: member cannot remove another member
select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.remove_household_member('11111111-1111-1111-1111-111111111111'::uuid) $$,
  '42501',
  'Not authorized or target is not a member',
  'member cannot remove another member'
);

-- Test: owner can list pending invites and revoke
select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

-- Insert a fresh pending invite for testing revoke
insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'newinvite@example.com',
  'revoke-test-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

select is(
  (select count(*) from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)),
  1::bigint,
  'owner can list pending invites for household'
);

select lives_ok(
  $$ select public.revoke_household_invite('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) $$,
  'owner can revoke pending invite'
);

select is(
  (
    select status from public.household_invites
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
  ),
  'revoked',
  'revoked invite has revoked status'
);

-- Test: member cannot revoke invite
-- Insert another invite for this test
insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'another@example.com',
  'member-revoke-test-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.revoke_household_invite('ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid) $$,
  '42501',
  'Not authorized or invite not found',
  'member cannot revoke invite'
);

-- Test: member cannot list owner pending invites
select throws_ok(
  $$ select * from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  '42501',
  'Not authorized',
  'member cannot list owner pending invites'
);

reset role;

select * from finish();

rollback;
