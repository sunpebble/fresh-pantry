-- Food-log entries: household-scoped, realtime-synced, append-only.
--
-- Mirrors public.meal_plan_entries: an opaque jsonb `payload`
-- (name, category, outcome, loggedAt, wasExpiring) plus the standard sync
-- columns. Optimistic-concurrency reuses app_private.bump_row_version.
-- Append-only in the client; `deleted_at` only set when a manual removal's
-- logged departure is undone.

create table public.food_log_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  payload jsonb not null,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index food_log_entries_household_updated_idx
  on public.food_log_entries (household_id, updated_at);

grant select, insert, update, delete on public.food_log_entries to authenticated;

alter table public.food_log_entries enable row level security;

create policy "food_log_entries_member_all" on public.food_log_entries
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

-- Make `version` server-authoritative (only ever +1 per update), same as the
-- other synced tables — defends the client's conditional-write conflict guard.
drop trigger if exists food_log_entries_bump_version on public.food_log_entries;
create trigger food_log_entries_bump_version
  before update on public.food_log_entries
  for each row
  execute function app_private.bump_row_version();

-- Add to the realtime publication so household members get live updates
-- (idempotent, same guard pattern as the init migration).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'food_log_entries'
    ) then
      execute 'alter publication supabase_realtime add table public.food_log_entries';
    end if;
  end if;
end;
$$;
