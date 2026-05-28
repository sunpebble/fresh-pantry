-- Open household invites allow owners to share one-time links or QR codes
-- without binding the invite to a specific email address.
alter table public.household_invites
  alter column email drop not null;

create or replace function app_private.accept_household_invite_record(
  target_invite_id uuid,
  target_invite_token_hash text
)
returns public.household_members
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  invite_record public.household_invites;
  accepted_member public.household_members;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select *
  into invite_record
  from public.household_invites hi
  where (
      target_invite_id is not null
      and hi.id = target_invite_id
    )
    or (
      target_invite_token_hash is not null
      and hi.token_hash = target_invite_token_hash
    )
  for update;

  if not found
    or invite_record.status <> 'pending'
    or invite_record.expires_at <= now()
  then
    raise exception 'Invite is not available' using errcode = 'P0001';
  end if;

  if nullif(trim(invite_record.email), '') is not null
    and (current_email = '' or lower(invite_record.email) <> current_email)
  then
    raise exception 'Invite email does not match authenticated user' using errcode = '42501';
  end if;

  insert into public.household_members (household_id, user_id, role)
  values (invite_record.household_id, current_user_id, 'member')
  on conflict (household_id, user_id) do nothing
  returning *
  into accepted_member;

  if accepted_member.household_id is null then
    select *
    into accepted_member
    from public.household_members hm
    where hm.household_id = invite_record.household_id
      and hm.user_id = current_user_id;
  end if;

  update public.household_invites
  set status = 'accepted',
      accepted_by = current_user_id,
      accepted_at = now()
  where id = invite_record.id;

  return accepted_member;
end;
$$;

create or replace function public.preview_household_invite(invite_token_hash text)
returns table (
  household_id uuid,
  household_name text,
  owner_email text,
  invited_email text,
  member_count integer,
  inventory_count integer,
  shopping_count integer,
  custom_recipe_count integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  invite_record public.household_invites;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select *
  into invite_record
  from public.household_invites
  where token_hash = invite_token_hash;

  if not found
    or invite_record.status <> 'pending'
    or invite_record.expires_at <= now()
  then
    raise exception 'Invite is not available' using errcode = 'P0001';
  end if;

  if nullif(trim(invite_record.email), '') is not null
    and (current_email = '' or lower(invite_record.email) <> current_email)
  then
    raise exception 'Invite email does not match authenticated user' using errcode = '42501';
  end if;

  return query
  select
    h.id,
    h.name,
    coalesce(p.email, u.email, ''),
    coalesce(invite_record.email, ''),
    (
      select count(*)::integer
      from public.household_members hm
      where hm.household_id = invite_record.household_id
    ),
    (
      select count(*)::integer
      from public.inventory_items ii
      where ii.household_id = invite_record.household_id
        and ii.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.shopping_items si
      where si.household_id = invite_record.household_id
        and si.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.custom_recipes cr
      where cr.household_id = invite_record.household_id
        and cr.deleted_at is null
    ),
    invite_record.expires_at
  from public.households h
  left join public.profiles p on p.id = h.owner_id
  left join auth.users u on u.id = h.owner_id
  where h.id = invite_record.household_id;
end;
$$;

create or replace function public.list_pending_household_invites()
returns table (
  invite_id uuid,
  household_id uuid,
  household_name text,
  owner_email text,
  invited_email text,
  member_count integer,
  inventory_count integer,
  shopping_count integer,
  custom_recipe_count integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if current_email = '' then
    return;
  end if;

  return query
  select
    hi.id,
    h.id,
    h.name,
    coalesce(p.email, u.email, ''),
    coalesce(hi.email, ''),
    (
      select count(*)::integer
      from public.household_members hm
      where hm.household_id = hi.household_id
    ),
    (
      select count(*)::integer
      from public.inventory_items ii
      where ii.household_id = hi.household_id
        and ii.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.shopping_items si
      where si.household_id = hi.household_id
        and si.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.custom_recipes cr
      where cr.household_id = hi.household_id
        and cr.deleted_at is null
    ),
    hi.expires_at
  from public.household_invites hi
  join public.households h on h.id = hi.household_id
  left join public.profiles p on p.id = h.owner_id
  left join auth.users u on u.id = h.owner_id
  where nullif(trim(hi.email), '') is not null
    and lower(hi.email) = current_email
    and hi.status = 'pending'
    and hi.expires_at > now()
  order by hi.created_at asc;
end;
$$;

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
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.household_members o
    where o.household_id = target_household_id
      and o.user_id = current_user_id
      and o.role = 'owner'
  ) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select hi.id, coalesce(hi.email, ''), hi.expires_at, hi.created_at
  from public.household_invites hi
  where hi.household_id = target_household_id
    and hi.status = 'pending'
    and hi.expires_at > now()
  order by hi.created_at desc;
end;
$$;
