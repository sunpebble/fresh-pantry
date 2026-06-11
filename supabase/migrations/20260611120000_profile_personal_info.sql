-- Personal profile: nickname + avatar; surface them through the members RPC; an
-- avatars Storage bucket (public read, owner-only write). profiles stays
-- user-scoped (PK = auth.users.id) — no version/client columns, single writer.

alter table public.profiles
  add column if not exists nickname text,
  add column if not exists avatar_path text;

-- Extend list_household_members to carry profile display fields. It is
-- security definer and already left-joins profiles, so members see each other's
-- display_name/nickname/avatar_path WITHOUT widening the profiles select RLS.
-- DROP first: CREATE OR REPLACE cannot change a function's RETURNS TABLE shape
-- (adding columns is an OUT-parameter signature change → "cannot change return
-- type of existing function"), so the prior 4-column definition is dropped first.
drop function if exists public.list_household_members(uuid);
create function public.list_household_members(target_household_id uuid)
returns table (
  household_id uuid,
  user_id uuid,
  role text,
  email text,
  display_name text,
  nickname text,
  avatar_path text
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
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = current_user_id
  ) then
    raise exception 'Household access denied' using errcode = '42501';
  end if;

  return query
  select
    hm.household_id,
    hm.user_id,
    hm.role,
    coalesce(p.email, u.email, ''),
    coalesce(p.display_name, ''),
    coalesce(p.nickname, ''),
    coalesce(p.avatar_path, '')
  from public.household_members hm
  left join public.profiles p on p.id = hm.user_id
  left join auth.users u on u.id = hm.user_id
  where hm.household_id = target_household_id
  order by
    case hm.role when 'owner' then 0 else 1 end,
    lower(coalesce(p.email, u.email, '')),
    hm.joined_at;
end;
$$;

revoke all on function public.list_household_members(uuid) from public;
revoke all on function public.list_household_members(uuid) from anon;
grant execute on function public.list_household_members(uuid) to authenticated;

-- Avatars bucket: public read (display via getPublicURL), owner-only write.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- A user may only write objects under their own {auth.uid()}/ prefix.
-- Drop-then-create keeps the migration idempotent (repo convention, cf.
-- 20260529090000_harden_household_security.sql).
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
