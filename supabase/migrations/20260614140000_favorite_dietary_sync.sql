-- 收藏菜谱 / 忌口关键字 家庭同步:两张 set-membership 表。
-- 结构与 food_log_entries 完全平行(payload jsonb + 4 个同步列 + member_all RLS
-- + bump_version 触发器 + realtime publication)。差异:`id` 由客户端提供 —
-- 确定性 uuid 形状(SHA256(namespace+household+key) 前 16 字节),同一 (家庭, recipe/
-- keyword) 在所有设备解析到同一行 → last-write-wins 收敛;取消收藏 / 移除忌口 = 软删。

-- ============================ favorite_recipes ============================

create table public.favorite_recipes (
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

create index favorite_recipes_household_updated_idx
  on public.favorite_recipes (household_id, updated_at);

grant select, insert, update, delete on public.favorite_recipes to authenticated;

alter table public.favorite_recipes enable row level security;

create policy "favorite_recipes_member_all" on public.favorite_recipes
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

drop trigger if exists favorite_recipes_bump_version on public.favorite_recipes;
create trigger favorite_recipes_bump_version
  before update on public.favorite_recipes
  for each row
  execute function app_private.bump_row_version();

-- =========================== dietary_preferences ==========================

create table public.dietary_preferences (
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

create index dietary_preferences_household_updated_idx
  on public.dietary_preferences (household_id, updated_at);

grant select, insert, update, delete on public.dietary_preferences to authenticated;

alter table public.dietary_preferences enable row level security;

create policy "dietary_preferences_member_all" on public.dietary_preferences
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

drop trigger if exists dietary_preferences_bump_version on public.dietary_preferences;
create trigger dietary_preferences_bump_version
  before update on public.dietary_preferences
  for each row
  execute function app_private.bump_row_version();

-- =============================== realtime ================================

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'favorite_recipes'
    ) then
      execute 'alter publication supabase_realtime add table public.favorite_recipes';
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'dietary_preferences'
    ) then
      execute 'alter publication supabase_realtime add table public.dietary_preferences';
    end if;
  end if;
end;
$$;
