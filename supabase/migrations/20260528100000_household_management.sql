-- remove_household_member: owner removes a member from their household
create or replace function public.remove_household_member(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  matched_household_id uuid;
  current_user_id uuid := (select auth.uid());
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
  matched_household_id uuid;
  current_user_id uuid := (select auth.uid());
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
  current_user_id uuid := (select auth.uid());
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
