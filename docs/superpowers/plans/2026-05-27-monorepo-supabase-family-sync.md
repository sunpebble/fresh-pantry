# Monorepo Supabase Family Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Fresh Pantry into a monorepo and ship first-phase local-first Supabase household sharing with a thin Cloudflare Worker at `api.fresh-pantry.kunish.eu.org`.

**Architecture:** Move the existing Flutter app to `apps/mobile/`, keep its Riverpod and `StorageAdapter` boundaries, and add a sync layer beside the current local repositories. Supabase owns Auth, household membership, shared pantry data, RLS, and Realtime. Cloudflare Worker only provides `/health` and invite deep-link routing in this phase.

**Tech Stack:** Flutter, Riverpod, SharedPreferences, Supabase Flutter, Supabase CLI/Postgres/RLS/Realtime, Cloudflare Workers, Wrangler, TypeScript, Vitest.

---

## Scope And Sequencing

This plan implements the approved design in reviewable stages. Each stage leaves the repository in a runnable state and ends with a commit.

The first execution session should start from an isolated worktree via `superpowers:using-git-worktrees`. This plan assumes the current branch already contains the approved design doc:

```text
docs/superpowers/specs/2026-05-27-monorepo-supabase-family-sync-design.md
```

## File Structure Map

### Root

| Path | Responsibility |
|---|---|
| `package.json` | Root scripts for mobile, API, and Supabase workflows. |
| `.gitignore` | Keep generated Flutter, Node, Supabase, and local env artifacts out of git. |
| `README.md` | Monorepo entry point with workflow commands. |

### Mobile App

| Path | Responsibility |
|---|---|
| `apps/mobile/` | Existing Flutter app moved intact from repo root. |
| `apps/mobile/lib/config/backend_config.dart` | Reads Supabase URL/key and Worker base URL from Dart defines. |
| `apps/mobile/lib/backend/supabase_client_provider.dart` | Initializes and exposes Supabase client through Riverpod. |
| `apps/mobile/lib/models/sync_metadata.dart` | Shared remote id/version/delete metadata value object. |
| `apps/mobile/lib/sync/sync_operation.dart` | Serializable local outbox operation model. |
| `apps/mobile/lib/sync/sync_outbox_repo.dart` | Persists pending operations through `StorageAdapter`. |
| `apps/mobile/lib/sync/merge_policy.dart` | Deterministic local/remote merge rules. |
| `apps/mobile/lib/sync/remote_pantry_repository.dart` | Typed interface and Supabase implementation for household data. |
| `apps/mobile/lib/sync/sync_coordinator.dart` | Push, pull, Realtime application, cursor handling, and conflict recording. |
| `apps/mobile/lib/household/household_models.dart` | Household, member, invite, and session value objects. |
| `apps/mobile/lib/household/household_session_controller.dart` | Auth state, selected household, create household, invite acceptance. |
| `apps/mobile/lib/screens/auth_gate_screen.dart` | Login and household setup gate. |
| `apps/mobile/lib/widgets/settings/household_section.dart` | Household members, invite form, and sync status in settings. |

### Supabase

| Path | Responsibility |
|---|---|
| `supabase/config.toml` | Local Supabase CLI configuration. |
| `supabase/migrations/*_init_family_sync_schema.sql` | Schema, RLS, helper functions, indexes, Realtime publication. |
| `supabase/tests/family_sync_rls.sql` | RLS smoke tests for owner/member/non-member access. |
| `supabase/seed.sql` | Intentionally empty; local resets should not fill demo data. |

### Cloudflare Worker

| Path | Responsibility |
|---|---|
| `apps/api/src/index.ts` | Worker request handler for `/health` and `/invite/:token`. |
| `apps/api/test/index.test.ts` | Worker route tests. |
| `apps/api/wrangler.jsonc` | Worker name, compatibility date, and custom domain route. |
| `apps/api/package.json` | API scripts and dependencies. |
| `apps/api/tsconfig.json` | TypeScript config. |
| `apps/api/vitest.config.ts` | Vitest config for Worker tests. |

---

## Task 1: Move Flutter App Into `apps/mobile`

**Files:**
- Move: `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`, `lib/`, `test/`, `assets/`, `google_fonts/`, `third_party/`, `design/`, `stitch-assets/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata` to `apps/mobile/`
- Modify: `.gitignore`
- Modify: `README.md`
- Create: `package.json`

- [ ] **Step 1: Record the pre-move baseline**

Run:

```bash
git status --short --branch
flutter analyze
flutter test
```

Expected:

```text
flutter analyze exits 0
flutter test exits 0
```

- [ ] **Step 2: Move the Flutter package**

Run:

```bash
mkdir -p apps/mobile
git mv android apps/mobile/android
git mv ios apps/mobile/ios
git mv macos apps/mobile/macos
git mv linux apps/mobile/linux
git mv windows apps/mobile/windows
git mv web apps/mobile/web
git mv lib apps/mobile/lib
git mv test apps/mobile/test
git mv assets apps/mobile/assets
git mv google_fonts apps/mobile/google_fonts
git mv third_party apps/mobile/third_party
git mv design apps/mobile/design
git mv stitch-assets apps/mobile/stitch-assets
git mv pubspec.yaml apps/mobile/pubspec.yaml
git mv pubspec.lock apps/mobile/pubspec.lock
git mv analysis_options.yaml apps/mobile/analysis_options.yaml
git mv .metadata apps/mobile/.metadata
```

Expected: `git status --short` shows only renames for mobile files.

- [ ] **Step 3: Replace root README with monorepo entry point**

Write `README.md`:

```markdown
# Fresh Pantry

Fresh Pantry is a local-first household pantry app with a Flutter mobile client, Supabase-backed family sharing, and a thin Cloudflare Worker API surface.

## Layout

- `apps/mobile` - Flutter app.
- `apps/api` - Cloudflare Worker for health checks and invite deep links.
- `supabase` - Supabase migrations, tests, and local configuration.
- `docs/superpowers` - design specs and implementation plans.

## Common Commands

```bash
npm run mobile:analyze
npm run mobile:test
npm run api:test
npm run supabase:status
```

Run mobile-specific Flutter commands from `apps/mobile` when debugging locally.

The API and Supabase workspaces are planned for later implementation tasks. Until those directories exist, these root scripts print what will be added and exit successfully; once the directories land, they run the real workspace commands:

```bash
npm run api:test
npm run api:deploy
npm run supabase:status
```
```

- [ ] **Step 4: Add root workspace scripts**

Create `package.json`:

```json
{
  "name": "fresh-pantry-monorepo",
  "private": true,
  "scripts": {
    "mobile:analyze": "cd apps/mobile && flutter analyze",
    "mobile:test": "cd apps/mobile && flutter test",
    "mobile:pub-get": "cd apps/mobile && flutter pub get",
    "api:test": "sh -c 'if [ -d apps/api ]; then cd apps/api && npm test; else echo \"apps/api will be added in Task 2\"; fi'",
    "api:deploy": "sh -c 'if [ -d apps/api ]; then cd apps/api && npx wrangler deploy; else echo \"apps/api will be added in Task 2\"; fi'",
    "supabase:start": "sh -c 'if [ -d supabase ]; then supabase start; else echo \"supabase project will be added in Task 3\"; fi'",
    "supabase:stop": "sh -c 'if [ -d supabase ]; then supabase stop; else echo \"supabase project will be added in Task 3\"; fi'",
    "supabase:status": "sh -c 'if [ -d supabase ]; then supabase status; else echo \"supabase project will be added in Task 3\"; fi'",
    "supabase:reset": "sh -c 'if [ -d supabase ]; then supabase db reset; else echo \"supabase project will be added in Task 3\"; fi'",
    "check": "npm run mobile:analyze && npm run mobile:test"
  }
}
```

- [ ] **Step 5: Update root `.gitignore` for monorepo outputs**

Append these entries if they are not present:

```gitignore
# Monorepo generated outputs
**/.dart_tool/
**/.flutter-plugins
**/.flutter-plugins-dependencies
**/build/
**/coverage/
**/node_modules/
**/.wrangler/
**/.dev.vars
supabase/.branches/
supabase/.temp/
```

- [ ] **Step 6: Restore mobile dependencies from the new path**

Run:

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

Expected:

```text
flutter analyze exits 0
flutter test exits 0
```

- [ ] **Step 7: Commit the mechanical move**

Run:

```bash
git add -A
git diff --cached --check
git commit -m "chore: move Flutter app into monorepo"
```

---

## Task 2: Scaffold Cloudflare Worker API

**Files:**
- Create: `apps/api/package.json`
- Create: `apps/api/src/index.ts`
- Create: `apps/api/test/index.test.ts`
- Create: `apps/api/wrangler.jsonc`
- Create: `apps/api/tsconfig.json`
- Create: `apps/api/vitest.config.ts`

- [ ] **Step 1: Create the API package files**

Create `apps/api/package.json`:

```json
{
  "name": "@fresh-pantry/api",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.9.0",
    "@cloudflare/workers-types": "^4.20260516.0",
    "typescript": "^5.9.0",
    "vitest": "^3.2.0",
    "wrangler": "^4.18.0"
  }
}
```

Create `apps/api/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true
  },
  "include": ["src", "test", "vitest.config.ts"]
}
```

Create `apps/api/vitest.config.ts`:

```ts
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
      },
    },
  },
});
```

Create `apps/api/wrangler.jsonc`:

```jsonc
{
  "name": "fresh-pantry-api",
  "main": "src/index.ts",
  "compatibility_date": "2026-05-27",
  "routes": [
    {
      "pattern": "api.fresh-pantry.kunish.eu.org",
      "custom_domain": true
    }
  ]
}
```

- [ ] **Step 2: Write failing Worker tests**

Create `apps/api/test/index.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("fresh-pantry-api", () => {
  it("returns health status", async () => {
    const response = await worker.fetch(new Request("https://api.fresh-pantry.kunish.eu.org/health"));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      service: "fresh-pantry-api",
      ok: true,
    });
  });

  it("redirects valid invite tokens to the mobile deep link", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-"),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("freshpantry://invite/abcDEF123_-");
  });

  it("rejects malformed invite tokens", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/not valid"),
    );

    expect(response.status).toBe(400);
    await expect(response.text()).resolves.toContain("Invalid invite token");
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
cd apps/api
npm install
npm test
```

Expected: FAIL because `src/index.ts` does not exist.

- [ ] **Step 4: Implement Worker routes**

Create `apps/api/src/index.ts`:

```ts
const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{10,160}$/;

function json(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...init.headers,
    },
  });
}

function inviteFallback(token: string): Response {
  const deepLink = `freshpantry://invite/${encodeURIComponent(token)}`;
  return new Response(
    `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Open Fresh Pantry</title>
  </head>
  <body>
    <main>
      <h1>Open Fresh Pantry</h1>
      <p>Use the button below to accept this household invite.</p>
      <p><a href="${deepLink}">Open invite</a></p>
    </main>
  </body>
</html>`,
    { headers: { "content-type": "text/html; charset=utf-8" } },
  );
}

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({
        service: "fresh-pantry-api",
        ok: true,
        timestamp: new Date().toISOString(),
      });
    }

    const inviteMatch = url.pathname.match(/^\/invite\/([^/]+)$/);
    if (inviteMatch) {
      const token = decodeURIComponent(inviteMatch[1]);
      if (!INVITE_TOKEN_PATTERN.test(token)) {
        return new Response("Invalid invite token", { status: 400 });
      }
      const accept = request.headers.get("accept") ?? "";
      if (accept.includes("text/html")) {
        return inviteFallback(token);
      }
      return Response.redirect(`freshpantry://invite/${encodeURIComponent(token)}`, 302);
    }

    return new Response("Not found", { status: 404 });
  },
};
```

- [ ] **Step 5: Run Worker tests**

Run:

```bash
cd apps/api
npm test
```

Expected: PASS.

- [ ] **Step 6: Commit Worker scaffold**

Run:

```bash
git add apps/api package-lock.json
git diff --cached --check
git commit -m "feat(api): add worker health and invite routes"
```

---

## Task 3: Add Supabase Schema, RLS, And Local Tests

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/*_init_family_sync_schema.sql`
- Create: `supabase/tests/family_sync_rls.sql`
- Create: `supabase/seed.sql`

- [ ] **Step 1: Initialize Supabase project**

Run:

```bash
supabase init
supabase migration new init_family_sync_schema
```

Expected:

```text
supabase/config.toml exists
supabase/migrations/*_init_family_sync_schema.sql exists
```

- [ ] **Step 2: Write schema migration**

Open the generated migration:

```bash
MIGRATION="$(ls supabase/migrations/*_init_family_sync_schema.sql)"
printf '%s\n' "$MIGRATION"
```

Replace its contents with:

```sql
create schema if not exists app_private;

create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  default_storage_area text not null default 'fridge',
  category_preferences jsonb not null default '{}'::jsonb,
  unit_preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  quantity text not null,
  unit text not null,
  image_url text not null default '',
  freshness_percent numeric not null default 1,
  state text not null default 'fresh',
  expiry_label text,
  category text,
  barcode text,
  storage text not null default 'fridge',
  expiry_date timestamptz,
  added_at timestamptz,
  shelf_life_days integer,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  detail text not null default '',
  image_url text,
  category text not null default '其他',
  is_checked boolean not null default false,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.custom_recipes (
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

create table public.sync_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('inventory_item', 'shopping_item', 'custom_recipe', 'household_config')),
  entity_id uuid not null,
  operation text not null,
  patch jsonb not null default '{}'::jsonb,
  base_version integer,
  result_version integer,
  client_id text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index inventory_items_household_updated_idx on public.inventory_items (household_id, updated_at);
create index shopping_items_household_updated_idx on public.shopping_items (household_id, updated_at);
create index custom_recipes_household_updated_idx on public.custom_recipes (household_id, updated_at);
create index sync_events_household_created_idx on public.sync_events (household_id, created_at);
create index household_invites_email_status_idx on public.household_invites (lower(email), status);

create or replace function app_private.is_household_member(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = (select auth.uid())
  );
$$;

create or replace function app_private.is_household_owner(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = (select auth.uid())
      and hm.role = 'owner'
  );
$$;

revoke all on function app_private.is_household_member(uuid) from public;
revoke all on function app_private.is_household_owner(uuid) from public;
grant execute on function app_private.is_household_member(uuid) to authenticated;
grant execute on function app_private.is_household_owner(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.inventory_items enable row level security;
alter table public.shopping_items enable row level security;
alter table public.custom_recipes enable row level security;
alter table public.sync_events enable row level security;

create policy "profiles_select_self" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles_insert_self" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles_update_self" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "households_select_member" on public.households
  for select to authenticated
  using (app_private.is_household_member(id));

create policy "households_insert_owner" on public.households
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "households_update_owner" on public.households
  for update to authenticated
  using (app_private.is_household_owner(id))
  with check (app_private.is_household_owner(id));

create policy "household_members_select_member" on public.household_members
  for select to authenticated
  using (app_private.is_household_member(household_id));

create policy "household_members_insert_owner_or_self_owner" on public.household_members
  for insert to authenticated
  with check (
    app_private.is_household_owner(household_id)
    or (role = 'owner' and user_id = (select auth.uid()))
  );

create policy "household_members_delete_owner" on public.household_members
  for delete to authenticated
  using (app_private.is_household_owner(household_id) and role = 'member');

create policy "household_invites_select_owner" on public.household_invites
  for select to authenticated
  using (app_private.is_household_owner(household_id));

create policy "household_invites_insert_owner" on public.household_invites
  for insert to authenticated
  with check (app_private.is_household_owner(household_id) and created_by = (select auth.uid()));

create policy "household_invites_update_owner_or_accepting_email" on public.household_invites
  for update to authenticated
  using (
    app_private.is_household_owner(household_id)
    or (
      status = 'pending'
      and lower(email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
    )
  )
  with check (
    app_private.is_household_owner(household_id)
    or (
      status = 'accepted'
      and accepted_by = (select auth.uid())
      and lower(email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
    )
  );

create policy "inventory_items_member_all" on public.inventory_items
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "shopping_items_member_all" on public.shopping_items
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "custom_recipes_member_all" on public.custom_recipes
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "sync_events_member_all" on public.sync_events
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id) and created_by = (select auth.uid()));

alter publication supabase_realtime add table public.inventory_items;
alter publication supabase_realtime add table public.shopping_items;
alter publication supabase_realtime add table public.custom_recipes;
alter publication supabase_realtime add table public.sync_events;
```

- [ ] **Step 3: Keep local seed empty**

Create `supabase/seed.sql`:

```sql
-- Intentionally empty.
-- Local resets should start without demo accounts, households, or pantry data.
-- Database tests create their own fixtures in supabase/tests.
```

- [ ] **Step 4: Add RLS smoke tests**

Create `supabase/tests/family_sync_rls.sql`:
The test must insert its owner/member/outsider fixtures inside the test
transaction; it must not depend on `supabase/seed.sql`.

```sql
begin;

select plan(4);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
select set_config('request.jwt.claim.email', 'owner@example.com', true);
set local role authenticated;

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'owner can read household'
);

insert into public.inventory_items (household_id, name, quantity, unit, storage)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Milk', '1', 'box', 'fridge');

select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
select set_config('request.jwt.claim.email', 'member@example.com', true);

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'member can read shared inventory'
);

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
select set_config('request.jwt.claim.email', 'outsider@example.com', true);

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read household'
);

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read inventory'
);

select * from finish();

rollback;
```

- [ ] **Step 5: Run Supabase checks**

Run:

```bash
supabase start
supabase db reset
supabase test db
```

Expected:

```text
supabase db reset exits 0
supabase test db exits 0
```

- [ ] **Step 6: Commit Supabase schema**

Run:

```bash
git add supabase
git diff --cached --check
git commit -m "feat(supabase): add family sync schema"
```

---

## Task 4: Add Mobile Backend Configuration

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Create: `apps/mobile/lib/config/backend_config.dart`
- Create: `apps/mobile/test/backend_config_test.dart`

- [ ] **Step 1: Add mobile dependencies**

Run:

```bash
cd apps/mobile
flutter pub add supabase_flutter uuid crypto app_links
flutter pub get
```

Expected: `pubspec.yaml` includes `supabase_flutter`, `uuid`, `crypto`, and `app_links`.

- [ ] **Step 2: Write config tests**

Create `apps/mobile/test/backend_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/config/backend_config.dart';

void main() {
  test('BackendConfig validates required values', () {
    expect(
      () => const BackendConfig(
        supabaseUrl: '',
        supabasePublishableKey: 'key',
        apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );
  });

  test('BackendConfig accepts complete values', () {
    const config = BackendConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'publishable',
      apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
    );

    expect(config.validate(), config);
  });
}
```

- [ ] **Step 3: Implement backend config**

Create `apps/mobile/lib/config/backend_config.dart`:

```dart
class BackendConfigException implements Exception {
  const BackendConfigException(this.message);

  final String message;

  @override
  String toString() => 'BackendConfigException: $message';
}

class BackendConfig {
  const BackendConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.apiBaseUrl,
  });

  factory BackendConfig.fromEnvironment() {
    return const BackendConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      apiBaseUrl: String.fromEnvironment(
        'FRESH_PANTRY_API_BASE_URL',
        defaultValue: 'https://api.fresh-pantry.kunish.eu.org',
      ),
    ).validate();
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String apiBaseUrl;

  BackendConfig validate() {
    if (supabaseUrl.trim().isEmpty) {
      throw const BackendConfigException('SUPABASE_URL is required');
    }
    if (supabasePublishableKey.trim().isEmpty) {
      throw const BackendConfigException('SUPABASE_PUBLISHABLE_KEY is required');
    }
    final apiUri = Uri.tryParse(apiBaseUrl);
    if (apiUri == null || !apiUri.hasScheme || !apiUri.hasAuthority) {
      throw BackendConfigException('FRESH_PANTRY_API_BASE_URL is invalid: $apiBaseUrl');
    }
    return this;
  }
}
```

- [ ] **Step 4: Run config tests**

Run:

```bash
cd apps/mobile
flutter test test/backend_config_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit backend config**

Run:

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/config apps/mobile/test/backend_config_test.dart
git diff --cached --check
git commit -m "feat(mobile): add backend configuration"
```

---

## Task 5: Add Remote Identity Metadata To Local Models

**Files:**
- Modify: `apps/mobile/lib/models/ingredient.dart`
- Modify: `apps/mobile/lib/models/shopping_item.dart`
- Modify: `apps/mobile/lib/models/recipe.dart`
- Create: `apps/mobile/lib/models/sync_metadata.dart`
- Modify: `apps/mobile/test/model_serialization_test.dart`

- [ ] **Step 1: Add failing model serialization tests**

Append to `apps/mobile/test/model_serialization_test.dart`:

```dart
test('Ingredient preserves remote sync metadata', () {
  final item = Ingredient(
    id: '11111111-1111-1111-1111-111111111111',
    name: 'Milk',
    quantity: '1',
    unit: 'box',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    remoteVersion: 3,
    clientUpdatedAt: DateTime.utc(2026, 5, 27),
    deletedAt: DateTime.utc(2026, 5, 28),
  );

  final decoded = Ingredient.fromJson(item.toJson());

  expect(decoded.id, item.id);
  expect(decoded.remoteVersion, 3);
  expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
  expect(decoded.deletedAt, DateTime.utc(2026, 5, 28));
});

test('ShoppingItem preserves remote sync metadata', () {
  final item = ShoppingItem(
    id: '22222222-2222-2222-2222-222222222222',
    name: 'Rice',
    detail: '5kg',
    category: '主食',
    remoteVersion: 4,
    clientUpdatedAt: DateTime.utc(2026, 5, 27),
  );

  final decoded = ShoppingItem.fromJson(item.toJson());

  expect(decoded.id, item.id);
  expect(decoded.remoteVersion, 4);
  expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
});

test('Recipe preserves remote sync metadata', () {
  final recipe = Recipe(
    id: '33333333-3333-3333-3333-333333333333',
    name: 'Soup',
    category: '晚餐',
    difficulty: 2,
    cookingMinutes: 30,
    description: 'Simple soup',
    ingredients: const [],
    steps: const ['Cook'],
    remoteVersion: 2,
    clientUpdatedAt: DateTime.utc(2026, 5, 27),
  );

  final decoded = Recipe.fromJson(recipe.toJson());

  expect(decoded.id, recipe.id);
  expect(decoded.remoteVersion, 2);
  expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd apps/mobile
flutter test test/model_serialization_test.dart
```

Expected: FAIL because the new metadata fields do not exist.

- [ ] **Step 3: Add metadata value object**

Create `apps/mobile/lib/models/sync_metadata.dart`:

```dart
DateTime? dateTimeFromJsonValue(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}

String? dateTimeToJsonValue(DateTime? value) => value?.toIso8601String();

class SyncMetadata {
  const SyncMetadata({
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  });

  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;
}
```

- [ ] **Step 4: Add fields to models**

Modify `Ingredient`, `ShoppingItem`, and `Recipe`:

```dart
// Add to each model:
final int remoteVersion;
final DateTime? clientUpdatedAt;
final DateTime? deletedAt;

// Add constructor defaults:
this.remoteVersion = 0,
this.clientUpdatedAt,
this.deletedAt,

// Add copyWith parameters:
int? remoteVersion,
DateTime? clientUpdatedAt,
DateTime? deletedAt,

// Add JSON keys:
'remoteVersion': remoteVersion,
'clientUpdatedAt': clientUpdatedAt?.toIso8601String(),
'deletedAt': deletedAt?.toIso8601String(),

// Read JSON keys:
remoteVersion: (json['remoteVersion'] as num?)?.toInt() ?? 0,
clientUpdatedAt: dateTimeFromJsonValue(json['clientUpdatedAt']),
deletedAt: dateTimeFromJsonValue(json['deletedAt']),
```

For `Ingredient`, also add an `id` field because it currently has no stable remote identity:

```dart
final String id;
```

Apply these exact edits to the existing `Ingredient` implementation:

- Add `id` to `operator ==`.
- Add `id` to `hashCode`.
- Add `String? id` to `copyWith`.
- Pass `id: id ?? this.id` in `copyWith`.
- Add `'id': id` to `toJson()`.
- Add `id: json['id'] as String? ?? ''` to `Ingredient.fromJson`.

Use this constructor header:

```dart
const Ingredient({
  this.id = '',
  required this.name,
  required this.quantity,
  required this.unit,
  required this.imageUrl,
  required this.freshnessPercent,
  required this.state,
  this.expiryLabel,
  this.category,
  this.barcode,
  this.storage = IconType.fridge,
  this.expiryDate,
  this.addedAt,
  this.shelfLifeDays,
  this.remoteVersion = 0,
  this.clientUpdatedAt,
  this.deletedAt,
});
```

- [ ] **Step 5: Run model tests**

Run:

```bash
cd apps/mobile
flutter test test/model_serialization_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 6: Commit model metadata**

Run:

```bash
git add apps/mobile/lib/models apps/mobile/test/model_serialization_test.dart
git diff --cached --check
git commit -m "feat(mobile): add sync metadata to pantry models"
```

---

## Task 6: Add Sync Outbox Persistence

**Files:**
- Create: `apps/mobile/lib/sync/sync_operation.dart`
- Create: `apps/mobile/lib/sync/sync_outbox_repo.dart`
- Create: `apps/mobile/test/sync_outbox_repo_test.dart`

- [ ] **Step 1: Write failing outbox tests**

Create `apps/mobile/test/sync_outbox_repo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

void main() {
  test('SyncOutboxRepo saves and loads pending operations', () async {
    final repo = SyncOutboxRepo(InMemoryStorageAdapter());
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.shoppingItem,
      entityId: 'item_1',
      operation: SyncOperationType.update,
      patch: const {'isChecked': true},
      baseVersion: 2,
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );

    await repo.enqueue(operation);

    expect(repo.loadPending(), [operation]);
  });

  test('SyncOutboxRepo removes acknowledged operations', () async {
    final repo = SyncOutboxRepo(InMemoryStorageAdapter());
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.inventoryItem,
      entityId: 'item_1',
      operation: SyncOperationType.delete,
      patch: const {},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );

    await repo.enqueue(operation);
    await repo.removeAcknowledged({'op_1'});

    expect(repo.loadPending(), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd apps/mobile
flutter test test/sync_outbox_repo_test.dart
```

Expected: FAIL because sync files do not exist.

- [ ] **Step 3: Implement sync operation model**

Create `apps/mobile/lib/sync/sync_operation.dart`:

```dart
enum SyncEntityType { inventoryItem, shoppingItem, customRecipe, householdConfig }

enum SyncOperationType { create, update, delete, intake, deduction, toggleChecked }

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.householdId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.patch,
    this.baseVersion,
    required this.clientId,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
  });

  final String id;
  final String householdId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperationType operation;
  final Map<String, dynamic> patch;
  final int? baseVersion;
  final String clientId;
  final DateTime createdAt;
  final int attemptCount;
  final String? lastError;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'householdId': householdId,
      'entityType': entityType.name,
      'entityId': entityId,
      'operation': operation.name,
      'patch': patch,
      'baseVersion': baseVersion,
      'clientId': clientId,
      'createdAt': createdAt.toIso8601String(),
      'attemptCount': attemptCount,
      'lastError': lastError,
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String? ?? '',
      householdId: json['householdId'] as String? ?? '',
      entityType: SyncEntityType.values.byName(json['entityType'] as String? ?? 'inventoryItem'),
      entityId: json['entityId'] as String? ?? '',
      operation: SyncOperationType.values.byName(json['operation'] as String? ?? 'update'),
      patch: Map<String, dynamic>.from(json['patch'] as Map? ?? const {}),
      baseVersion: (json['baseVersion'] as num?)?.toInt(),
      clientId: json['clientId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncOperation &&
        id == other.id &&
        householdId == other.householdId &&
        entityType == other.entityType &&
        entityId == other.entityId &&
        operation == other.operation &&
        baseVersion == other.baseVersion &&
        clientId == other.clientId &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode => Object.hash(id, householdId, entityType, entityId, operation, baseVersion, clientId, createdAt);
}
```

- [ ] **Step 4: Implement outbox repo**

Create `apps/mobile/lib/sync/sync_outbox_repo.dart`:

```dart
import 'dart:convert';

import '../storage/storage_adapter.dart';
import '../utils/json_object_list.dart';
import 'sync_operation.dart';

class SyncOutboxRepo {
  SyncOutboxRepo(this._adapter);

  static const storageKey = 'sync_outbox_v1';

  final StorageAdapter _adapter;

  List<SyncOperation> loadPending() {
    final raw = _adapter.read(storageKey);
    if (raw == null) return const [];
    try {
      return decodeJsonObjectList(raw).map(SyncOperation.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueue(SyncOperation operation) async {
    final pending = [...loadPending(), operation];
    await _save(pending);
  }

  Future<void> removeAcknowledged(Set<String> operationIds) async {
    final pending = loadPending().where((operation) => !operationIds.contains(operation.id)).toList();
    await _save(pending);
  }

  Future<void> replaceAll(List<SyncOperation> operations) {
    return _save(operations);
  }

  Future<void> _save(List<SyncOperation> operations) {
    return _adapter.write(
      storageKey,
      json.encode(operations.map((operation) => operation.toJson()).toList()),
    );
  }
}
```

- [ ] **Step 5: Run outbox tests**

Run:

```bash
cd apps/mobile
flutter test test/sync_outbox_repo_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 6: Commit outbox**

Run:

```bash
git add apps/mobile/lib/sync apps/mobile/test/sync_outbox_repo_test.dart
git diff --cached --check
git commit -m "feat(mobile): add sync outbox"
```

---

## Task 7: Add Merge Policy

**Files:**
- Create: `apps/mobile/lib/sync/merge_policy.dart`
- Create: `apps/mobile/test/merge_policy_test.dart`

- [ ] **Step 1: Write failing merge tests**

Create `apps/mobile/test/merge_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/merge_policy.dart';

void main() {
  test('mergePatch applies local patch when versions match', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '1'},
      remote: const {'name': 'Milk', 'quantity': '1'},
      patch: const {'quantity': '2'},
      baseVersion: 1,
      remoteVersion: 1,
    );

    expect(result.value['quantity'], '2');
    expect(result.conflict, isFalse);
  });

  test('mergePatch merges different changed fields', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '2', 'category': 'Dairy'},
      remote: const {'name': 'Milk', 'quantity': '1', 'category': 'Cold'},
      patch: const {'quantity': '3'},
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.value['quantity'], '3');
    expect(result.value['category'], 'Cold');
    expect(result.conflict, isFalse);
  });

  test('mergePatch records conflict for same-field edits', () {
    final result = mergeRemotePatch(
      local: const {'name': 'Milk', 'quantity': '2'},
      remote: const {'name': 'Milk', 'quantity': '3'},
      patch: const {'quantity': '4'},
      baseVersion: 1,
      remoteVersion: 2,
    );

    expect(result.value['quantity'], '4');
    expect(result.conflict, isTrue);
    expect(result.conflictFields, ['quantity']);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd apps/mobile
flutter test test/merge_policy_test.dart
```

Expected: FAIL because `merge_policy.dart` does not exist.

- [ ] **Step 3: Implement merge policy**

Create `apps/mobile/lib/sync/merge_policy.dart`:

```dart
class MergeResult {
  const MergeResult({
    required this.value,
    required this.conflict,
    this.conflictFields = const [],
  });

  final Map<String, dynamic> value;
  final bool conflict;
  final List<String> conflictFields;
}

MergeResult mergeRemotePatch({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required Map<String, dynamic> patch,
  required int? baseVersion,
  required int remoteVersion,
}) {
  if (baseVersion == null || baseVersion == remoteVersion) {
    return MergeResult(value: {...remote, ...patch}, conflict: false);
  }

  final merged = Map<String, dynamic>.from(remote);
  final conflicts = <String>[];

  for (final entry in patch.entries) {
    final field = entry.key;
    final localValue = local[field];
    final remoteValue = remote[field];
    final patchValue = entry.value;

    if (remoteValue == localValue || remoteValue == patchValue) {
      merged[field] = patchValue;
      continue;
    }

    merged[field] = patchValue;
    conflicts.add(field);
  }

  return MergeResult(
    value: merged,
    conflict: conflicts.isNotEmpty,
    conflictFields: conflicts,
  );
}
```

- [ ] **Step 4: Run merge tests**

Run:

```bash
cd apps/mobile
flutter test test/merge_policy_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit merge policy**

Run:

```bash
git add apps/mobile/lib/sync/merge_policy.dart apps/mobile/test/merge_policy_test.dart
git diff --cached --check
git commit -m "feat(mobile): add sync merge policy"
```

---

## Task 8: Add Supabase Client Provider And Remote Repository

**Files:**
- Create: `apps/mobile/lib/backend/supabase_client_provider.dart`
- Create: `apps/mobile/lib/household/household_models.dart`
- Create: `apps/mobile/lib/sync/remote_pantry_repository.dart`
- Create: `apps/mobile/test/remote_pantry_repository_test.dart`

- [ ] **Step 1: Write repository mapping tests**

Create `apps/mobile/test/remote_pantry_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/remote_pantry_repository.dart';

void main() {
  test('inventoryRowFromJson maps Supabase row to domain map', () {
    final row = {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Milk',
      'quantity': '1',
      'unit': 'box',
      'image_url': '',
      'freshness_percent': 1,
      'state': 'fresh',
      'storage': 'fridge',
      'version': 2,
    };

    final mapped = inventoryRowFromJson(row);

    expect(mapped['id'], row['id']);
    expect(mapped['imageUrl'], '');
    expect(mapped['freshnessPercent'], 1);
    expect(mapped['remoteVersion'], 2);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd apps/mobile
flutter test test/remote_pantry_repository_test.dart
```

Expected: FAIL because `remote_pantry_repository.dart` does not exist.

- [ ] **Step 3: Implement Supabase client provider**

Create `apps/mobile/lib/backend/supabase_client_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
```

- [ ] **Step 4: Implement household models**

Create `apps/mobile/lib/household/household_models.dart`:

```dart
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.defaultStorageArea,
  });

  final String id;
  final String name;
  final String ownerId;
  final String defaultStorageArea;

  factory Household.fromJson(Map<String, dynamic> json) {
    return Household(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      defaultStorageArea: json['default_storage_area'] as String? ?? 'fridge',
    );
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.householdId,
    required this.userId,
    required this.role,
    required this.email,
  });

  final String householdId;
  final String userId;
  final String role;
  final String email;
}
```

- [ ] **Step 5: Implement remote repository skeleton and row mappers**

Create `apps/mobile/lib/sync/remote_pantry_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../household/household_models.dart';

Map<String, dynamic> inventoryRowFromJson(Map<String, dynamic> row) {
  return {
    'id': row['id'],
    'name': row['name'],
    'quantity': row['quantity'],
    'unit': row['unit'],
    'imageUrl': row['image_url'] ?? '',
    'freshnessPercent': (row['freshness_percent'] as num?)?.toDouble() ?? 1.0,
    'state': row['state'] ?? 'fresh',
    'expiryLabel': row['expiry_label'],
    'category': row['category'],
    'barcode': row['barcode'],
    'storage': row['storage'],
    'expiryDate': row['expiry_date'],
    'addedAt': row['added_at'],
    'shelfLifeDays': row['shelf_life_days'],
    'remoteVersion': row['version'],
    'clientUpdatedAt': row['client_updated_at'],
    'deletedAt': row['deleted_at'],
  };
}

abstract class RemotePantryRepository {
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<List<Map<String, dynamic>>> loadInventory(String householdId);
  Future<void> upsertInventory(String householdId, List<Map<String, dynamic>> rows);
}

class SupabaseRemotePantryRepository implements RemotePantryRepository {
  SupabaseRemotePantryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Household>> loadHouseholds() async {
    final rows = await _client.from('households').select();
    return rows.map((row) => Household.fromJson(row)).toList();
  }

  @override
  Future<Household> createHousehold(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create household without a signed-in user.');
    }

    final row = await _client
        .from('households')
        .insert({'name': name, 'owner_id': userId})
        .select()
        .single();
    await _client.from('household_members').insert({
      'household_id': row['id'],
      'user_id': userId,
      'role': 'owner',
    });
    return Household.fromJson(row);
  }

  @override
  Future<List<Map<String, dynamic>>> loadInventory(String householdId) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    return rows.map(inventoryRowFromJson).toList();
  }

  @override
  Future<void> upsertInventory(String householdId, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('inventory_items').upsert(rows);
  }
}
```

- [ ] **Step 6: Run remote repo tests**

Run:

```bash
cd apps/mobile
flutter test test/remote_pantry_repository_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 7: Commit remote repository skeleton**

Run:

```bash
git add apps/mobile/lib/backend apps/mobile/lib/household apps/mobile/lib/sync/remote_pantry_repository.dart apps/mobile/test/remote_pantry_repository_test.dart
git diff --cached --check
git commit -m "feat(mobile): add Supabase pantry repository"
```

---

## Task 9: Initialize Supabase In Mobile Startup

**Files:**
- Modify: `apps/mobile/lib/main.dart`
- Modify: `apps/mobile/test/widget_test.dart`

- [ ] **Step 1: Write startup behavior expectation**

Modify `apps/mobile/test/widget_test.dart` so tests construct `FreshPantryApp` under explicit provider overrides instead of relying on `main()`. Keep the test focused on app rendering:

```dart
testWidgets('renders Fresh Pantry app shell', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = SharedPrefsStorageAdapter(prefs);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageAdapterProvider.overrideWithValue(adapter),
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      ],
      child: const FreshPantryApp(),
    ),
  );

  expect(find.byType(FreshPantryApp), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test**

Run:

```bash
cd apps/mobile
flutter test test/widget_test.dart
```

Expected: PASS before startup changes.

- [ ] **Step 3: Initialize Supabase in `main()`**

Modify `apps/mobile/lib/main.dart`:

```dart
import 'config/backend_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

Add before creating app services:

```dart
final backendConfig = BackendConfig.fromEnvironment();
await Supabase.initialize(
  url: backendConfig.supabaseUrl,
  publishableKey: backendConfig.supabasePublishableKey,
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
  ),
);
```

- [ ] **Step 4: Run mobile checks with Dart defines**

Run:

```bash
cd apps/mobile
flutter analyze
flutter test
flutter test --dart-define=SUPABASE_URL=https://example.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=publishable
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit Supabase initialization**

Run:

```bash
git add apps/mobile/lib/main.dart apps/mobile/test/widget_test.dart
git diff --cached --check
git commit -m "feat(mobile): initialize Supabase client"
```

---

## Task 10: Add Auth And Household Gate

**Files:**
- Create: `apps/mobile/lib/household/household_session_controller.dart`
- Create: `apps/mobile/lib/screens/auth_gate_screen.dart`
- Modify: `apps/mobile/lib/app.dart`
- Create: `apps/mobile/test/household_session_controller_test.dart`
- Create: `apps/mobile/test/auth_gate_screen_test.dart`

- [ ] **Step 1: Write controller tests with fake repository**

Create `apps/mobile/test/household_session_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  final households = <Household>[];
  var sentEmail = '';

  @override
  Future<void> sendOtp(String email) async {
    sentEmail = email;
  }

  @override
  Future<List<Household>> loadHouseholds() async => households;
}

void main() {
  test('sendOtp trims email before sending', () async {
    final gateway = FakeHouseholdGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.sendOtp(' owner@example.com ');

    expect(gateway.sentEmail, 'owner@example.com');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd apps/mobile
flutter test test/household_session_controller_test.dart
```

Expected: FAIL because the controller does not exist.

- [ ] **Step 3: Implement session controller skeleton**

Create `apps/mobile/lib/household/household_session_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_client_provider.dart';
import 'household_models.dart';

abstract class HouseholdGateway {
  Future<void> sendOtp(String email);
  Future<List<Household>> loadHouseholds();
}

class SupabaseHouseholdGateway implements HouseholdGateway {
  SupabaseHouseholdGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<void> sendOtp(String email) {
    return _client.auth.signInWithOtp(email: email);
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    final rows = await _client.from('households').select();
    return rows.map((row) => Household.fromJson(row)).toList();
  }
}

class HouseholdSessionState {
  const HouseholdSessionState({
    this.email = '',
    this.isSubmitting = false,
    this.error,
    this.households = const [],
  });

  final String email;
  final bool isSubmitting;
  final String? error;
  final List<Household> households;
}

class HouseholdSessionController extends StateNotifier<HouseholdSessionState> {
  HouseholdSessionController(this._gateway) : super(const HouseholdSessionState());

  final HouseholdGateway _gateway;

  Future<void> sendOtp(String email) async {
    final trimmed = email.trim();
    state = HouseholdSessionState(email: trimmed, isSubmitting: true);
    try {
      await _gateway.sendOtp(trimmed);
      state = HouseholdSessionState(email: trimmed);
    } catch (error) {
      state = HouseholdSessionState(email: trimmed, error: error.toString());
    }
  }

  Future<void> refreshHouseholds() async {
    final households = await _gateway.loadHouseholds();
    state = HouseholdSessionState(email: state.email, households: households);
  }
}

final householdGatewayProvider = Provider<HouseholdGateway>((ref) {
  return SupabaseHouseholdGateway(ref.read(supabaseClientProvider));
});

final householdSessionControllerProvider =
    StateNotifierProvider<HouseholdSessionController, HouseholdSessionState>((ref) {
  return HouseholdSessionController(ref.read(householdGatewayProvider));
});
```

- [ ] **Step 4: Add AuthGateScreen**

Create `apps/mobile/lib/screens/auth_gate_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_session_controller.dart';
import '../theme/app_spacing.dart';

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({
    super.key,
    required this.authenticatedChild,
  });

  final Widget authenticatedChild;

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(householdSessionControllerProvider);
    if (state.households.isNotEmpty) {
      return widget.authenticatedChild;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('登录 Fresh Pantry', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '邮箱'),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: state.isSubmitting
                    ? null
                    : () => ref.read(householdSessionControllerProvider.notifier).sendOtp(_emailController.text),
                child: Text(state.isSubmitting ? '发送中...' : '发送登录链接'),
              ),
              if (state.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(state.error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire app shell through auth gate**

Modify `apps/mobile/lib/app.dart` so `MaterialApp.home` uses `AuthGateScreen` instead of `AppShell`:

```dart
home: const AuthGateScreen(authenticatedChild: AppShell()),
```

Keep `AppShell` unchanged. Authenticated household users see the full app shell; unauthenticated users see the email OTP form.

- [ ] **Step 6: Run auth tests and full mobile test**

Run:

```bash
cd apps/mobile
flutter test test/household_session_controller_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 7: Commit auth gate**

Run:

```bash
git add apps/mobile/lib/household apps/mobile/lib/screens/auth_gate_screen.dart apps/mobile/lib/app.dart apps/mobile/test/household_session_controller_test.dart
git diff --cached --check
git commit -m "feat(mobile): add auth and household gate"
```

---

## Task 11: Add Household Bootstrap Upload

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Modify: `apps/mobile/lib/sync/remote_pantry_repository.dart`
- Create: `apps/mobile/test/household_bootstrap_test.dart`

- [ ] **Step 1: Write bootstrap test**

Create `apps/mobile/test/household_bootstrap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/household/household_models.dart';

class FakeBootstrapGateway implements HouseholdGateway {
  final created = <String>[];
  var uploadedInitialData = false;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<List<Household>> loadHouseholds() async => const [];

  Future<Household> createHousehold(String name) async {
    created.add(name);
    return const Household(
      id: 'household_1',
      name: 'Kunish Kitchen',
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    );
  }

  Future<void> uploadInitialData(String householdId) async {
    uploadedInitialData = householdId == 'household_1';
  }
}

void main() {
  test('createHousehold uploads local data before selecting household', () async {
    final gateway = FakeBootstrapGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.createHousehold('Kunish Kitchen');

    expect(gateway.created, ['Kunish Kitchen']);
    expect(gateway.uploadedInitialData, isTrue);
    expect(controller.state.households.single.id, 'household_1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd apps/mobile
flutter test test/household_bootstrap_test.dart
```

Expected: FAIL because `createHousehold` and `uploadInitialData` are not part of the gateway contract.

- [ ] **Step 3: Extend gateway contract and controller**

Modify `HouseholdGateway`:

```dart
Future<Household> createHousehold(String name);
Future<void> uploadInitialData(String householdId);
```

Add to `HouseholdSessionController`:

```dart
Future<void> createHousehold(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    state = HouseholdSessionState(email: state.email, error: '家庭名称不能为空');
    return;
  }
  state = HouseholdSessionState(email: state.email, isSubmitting: true, households: state.households);
  try {
    final household = await _gateway.createHousehold(trimmed);
    await _gateway.uploadInitialData(household.id);
    state = HouseholdSessionState(email: state.email, households: [household]);
  } catch (error) {
    state = HouseholdSessionState(email: state.email, error: error.toString(), households: state.households);
  }
}
```

- [ ] **Step 4: Implement Supabase bootstrap upload**

In `SupabaseHouseholdGateway`, inject local repositories through the constructor and wire them in `householdGatewayProvider` with explicit dependencies:

```dart
SupabaseHouseholdGateway(
  this._client,
  this._inventoryRepo,
  this._shoppingRepo,
  this._customRecipeRepo,
);
```

Update `householdGatewayProvider`:

```dart
final householdGatewayProvider = Provider<HouseholdGateway>((ref) {
  return SupabaseHouseholdGateway(
    ref.read(supabaseClientProvider),
    ref.read(inventoryRepoProvider),
    ref.read(shoppingRepoProvider),
    ref.read(customRecipeRepoProvider),
  );
});
```

Implement:

```dart
@override
Future<Household> createHousehold(String name) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) throw StateError('Cannot create household without a signed-in user.');
  final householdRow = await _client.from('households').insert({
    'name': name,
    'owner_id': userId,
  }).select().single();
  await _client.from('household_members').insert({
    'household_id': householdRow['id'],
    'user_id': userId,
    'role': 'owner',
  });
  return Household.fromJson(householdRow);
}

@override
Future<void> uploadInitialData(String householdId) async {
  final inventoryRows = _inventoryRepo.loadAll().map((item) => inventoryRowToSupabase(householdId, item)).toList();
  if (inventoryRows.isNotEmpty) {
    await _client.from('inventory_items').upsert(inventoryRows);
  }
  final shoppingRows = _shoppingRepo.loadAll().map((item) => shoppingRowToSupabase(householdId, item)).toList();
  if (shoppingRows.isNotEmpty) {
    await _client.from('shopping_items').upsert(shoppingRows);
  }
  final recipeRows = _customRecipeRepo.loadAll().map((recipe) => {
    'id': recipe.id,
    'household_id': householdId,
    'payload': recipe.toJson(),
    'version': recipe.remoteVersion == 0 ? 1 : recipe.remoteVersion,
  }).toList();
  if (recipeRows.isNotEmpty) {
    await _client.from('custom_recipes').upsert(recipeRows);
  }
}
```

- [ ] **Step 5: Run bootstrap tests**

Run:

```bash
cd apps/mobile
flutter test test/household_bootstrap_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 6: Commit bootstrap upload**

Run:

```bash
git add apps/mobile/lib/household apps/mobile/lib/sync/remote_pantry_repository.dart apps/mobile/test/household_bootstrap_test.dart
git diff --cached --check
git commit -m "feat(mobile): bootstrap household from local data"
```

---

## Task 12: Add Sync Coordinator Push/Pull

**Files:**
- Create: `apps/mobile/lib/sync/sync_coordinator.dart`
- Create: `apps/mobile/test/sync_coordinator_test.dart`
- Modify: `apps/mobile/lib/providers/storage_service_provider.dart`

- [ ] **Step 1: Write coordinator test**

Create `apps/mobile/test/sync_coordinator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

class FakeRemoteSyncGateway implements RemoteSyncGateway {
  final uploaded = <SyncOperation>[];

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    uploaded.addAll(operations);
    return operations.map((operation) => operation.id).toSet();
  }
}

void main() {
  test('pushPending uploads outbox operations and removes acknowledged ones', () async {
    final outbox = SyncOutboxRepo(InMemoryStorageAdapter());
    final remote = FakeRemoteSyncGateway();
    final coordinator = SyncCoordinator(outbox: outbox, remote: remote);
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.shoppingItem,
      entityId: 'item_1',
      operation: SyncOperationType.toggleChecked,
      patch: const {'isChecked': true},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );

    await outbox.enqueue(operation);
    await coordinator.pushPending();

    expect(remote.uploaded, [operation]);
    expect(outbox.loadPending(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd apps/mobile
flutter test test/sync_coordinator_test.dart
```

Expected: FAIL because `sync_coordinator.dart` does not exist.

- [ ] **Step 3: Implement sync coordinator**

Create `apps/mobile/lib/sync/sync_coordinator.dart`:

```dart
import 'sync_operation.dart';
import 'sync_outbox_repo.dart';

abstract class RemoteSyncGateway {
  Future<Set<String>> pushOperations(List<SyncOperation> operations);
}

class SyncCoordinator {
  SyncCoordinator({
    required SyncOutboxRepo outbox,
    required RemoteSyncGateway remote,
  })  : _outbox = outbox,
        _remote = remote;

  final SyncOutboxRepo _outbox;
  final RemoteSyncGateway _remote;

  Future<void> pushPending() async {
    final pending = _outbox.loadPending();
    if (pending.isEmpty) return;
    final acknowledged = await _remote.pushOperations(pending);
    await _outbox.removeAcknowledged(acknowledged);
  }
}
```

- [ ] **Step 4: Add provider wiring**

Modify `apps/mobile/lib/providers/storage_service_provider.dart`:

```dart
import '../sync/sync_outbox_repo.dart';

final syncOutboxRepoProvider = Provider<SyncOutboxRepo>((ref) {
  return SyncOutboxRepo(ref.read(storageAdapterProvider));
});
```

- [ ] **Step 5: Run coordinator tests**

Run:

```bash
cd apps/mobile
flutter test test/sync_coordinator_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 6: Commit sync coordinator**

Run:

```bash
git add apps/mobile/lib/sync/sync_coordinator.dart apps/mobile/lib/providers/storage_service_provider.dart apps/mobile/test/sync_coordinator_test.dart
git diff --cached --check
git commit -m "feat(mobile): add sync coordinator"
```

---

## Task 13: Enqueue Sync Operations From Notifiers

**Files:**
- Modify: `apps/mobile/lib/providers/inventory_provider.dart`
- Modify: `apps/mobile/lib/providers/shopping_provider.dart`
- Modify: `apps/mobile/lib/providers/custom_recipe_provider.dart`
- Create: `apps/mobile/test/sync_enqueue_provider_test.dart`

- [ ] **Step 1: Write provider enqueue test**

Create `apps/mobile/test/sync_enqueue_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

void main() {
  test('shopping toggle enqueues sync operation', () async {
    final adapter = InMemoryStorageAdapter();
    final outbox = SyncOutboxRepo(adapter);
    final container = ProviderContainer(
      overrides: [
        storageAdapterProvider.overrideWithValue(adapter),
        shoppingRepoProvider.overrideWithValue(ShoppingRepo(adapter)),
        syncOutboxRepoProvider.overrideWithValue(outbox),
      ],
    );
    addTearDown(container.dispose);

    await container.read(shoppingProvider.notifier).add(
      const ShoppingItem(
        id: 'item_1',
        name: 'Rice',
        detail: '',
        category: '主食',
      ),
    );
    await container.read(shoppingProvider.notifier).toggleCheck('item_1');

    expect(outbox.loadPending().map((operation) => operation.entityId), contains('item_1'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd apps/mobile
flutter test test/sync_enqueue_provider_test.dart
```

Expected: FAIL because notifiers do not enqueue outbox operations.

- [ ] **Step 3: Add enqueue helper to each notifier**

In each notifier, add a private method using `syncOutboxRepoProvider`:

```dart
Future<void> _enqueueSync(SyncOperation operation) {
  return ref.read(syncOutboxRepoProvider).enqueue(operation);
}
```

Use `Uuid().v4()` for operation ids and `DateTime.now().toUtc()` for `createdAt`.

For `ShoppingNotifier.toggleCheck`, enqueue:

```dart
await _enqueueSync(SyncOperation(
  id: const Uuid().v4(),
  householdId: ref.read(selectedHouseholdIdProvider),
  entityType: SyncEntityType.shoppingItem,
  entityId: id,
  operation: SyncOperationType.toggleChecked,
  patch: {'isChecked': updated.firstWhere((item) => item.id == id).isChecked},
  baseVersion: state.firstWhere((item) => item.id == id).remoteVersion,
  clientId: ref.read(syncClientIdProvider),
  createdAt: DateTime.now().toUtc(),
));
```

Create providers used by this code in a focused sync provider file:

```dart
final selectedHouseholdIdProvider = Provider<String>((ref) => '');
final syncClientIdProvider = Provider<String>((ref) => 'local-client');
```

Tests override these providers when a real household id is required.

- [ ] **Step 4: Run enqueue tests**

Run:

```bash
cd apps/mobile
flutter test test/sync_enqueue_provider_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit notifier enqueue wiring**

Run:

```bash
git add apps/mobile/lib/providers apps/mobile/lib/sync apps/mobile/test/sync_enqueue_provider_test.dart
git diff --cached --check
git commit -m "feat(mobile): enqueue local pantry changes"
```

---

## Task 14: Add Realtime Pull Application

**Files:**
- Modify: `apps/mobile/lib/sync/remote_pantry_repository.dart`
- Modify: `apps/mobile/lib/sync/sync_coordinator.dart`
- Create: `apps/mobile/test/realtime_sync_test.dart`

- [ ] **Step 1: Write Realtime application test**

Create `apps/mobile/test/realtime_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';

void main() {
  test('applyRemoteInventoryRows ignores soft-deleted rows', () {
    final rows = [
      {'id': 'item_1', 'name': 'Milk', 'deletedAt': null},
      {'id': 'item_2', 'name': 'Rice', 'deletedAt': '2026-05-27T00:00:00.000Z'},
    ];

    final visible = visibleRemoteRows(rows);

    expect(visible.map((row) => row['id']), ['item_1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd apps/mobile
flutter test test/realtime_sync_test.dart
```

Expected: FAIL because `visibleRemoteRows` does not exist.

- [ ] **Step 3: Add visible row helper and subscription API**

In `apps/mobile/lib/sync/sync_coordinator.dart`:

```dart
List<Map<String, dynamic>> visibleRemoteRows(List<Map<String, dynamic>> rows) {
  return rows.where((row) => row['deletedAt'] == null && row['deleted_at'] == null).toList();
}
```

In `RemotePantryRepository`, add methods:

```dart
Stream<List<Map<String, dynamic>>> watchInventory(String householdId);
Stream<List<Map<String, dynamic>>> watchShopping(String householdId);
Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId);
```

Implement with Supabase streams:

```dart
@override
Stream<List<Map<String, dynamic>>> watchInventory(String householdId) {
  return _client
      .from('inventory_items')
      .stream(primaryKey: ['id'])
      .eq('household_id', householdId)
      .map((rows) => rows.map(inventoryRowFromJson).toList());
}
```

- [ ] **Step 4: Run Realtime tests**

Run:

```bash
cd apps/mobile
flutter test test/realtime_sync_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit Realtime sync API**

Run:

```bash
git add apps/mobile/lib/sync apps/mobile/test/realtime_sync_test.dart
git diff --cached --check
git commit -m "feat(mobile): add realtime sync hooks"
```

---

## Task 15: Add Invite Creation And Acceptance

**Files:**
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Modify: `apps/mobile/lib/sync/remote_pantry_repository.dart`
- Create: `apps/mobile/lib/household/invite_token.dart`
- Create: `apps/mobile/test/invite_token_test.dart`
- Create: `apps/mobile/test/invite_acceptance_test.dart`

- [ ] **Step 1: Write invite token tests**

Create `apps/mobile/test/invite_token_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/invite_token.dart';

void main() {
  test('hashInviteToken returns stable sha256 hex', () {
    expect(
      hashInviteToken('abcDEF123_-'),
      '966149f22a6e83cf7cee9969192a095944b531cb0ebc15f4ded1e1cd71bf0368',
    );
  });

  test('isInviteTokenShapeValid rejects whitespace', () {
    expect(isInviteTokenShapeValid('abc DEF'), isFalse);
    expect(isInviteTokenShapeValid('abcDEF123_-'), isTrue);
  });
}
```

- [ ] **Step 2: Implement invite token helpers**

Create `apps/mobile/lib/household/invite_token.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final _random = Random.secure();
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{10,160}$');

String generateInviteToken() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  return List.generate(32, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
}

bool isInviteTokenShapeValid(String token) => _tokenPattern.hasMatch(token);

String hashInviteToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
```

- [ ] **Step 3: Add invite repository methods**

In `RemotePantryRepository`, add:

```dart
Future<String> createInvite({
  required String householdId,
  required String email,
});

Future<void> acceptInvite(String token);
```

In `SupabaseRemotePantryRepository`, implement:

```dart
@override
Future<String> createInvite({
  required String householdId,
  required String email,
}) async {
  final userId = _client.auth.currentUser?.id;
  if (userId == null) throw StateError('Cannot create invite without a signed-in user.');
  final token = generateInviteToken();
  await _client.from('household_invites').insert({
    'household_id': householdId,
    'email': email.trim(),
    'token_hash': hashInviteToken(token),
    'expires_at': DateTime.now().toUtc().add(const Duration(days: 14)).toIso8601String(),
    'created_by': userId,
  });
  return 'https://api.fresh-pantry.kunish.eu.org/invite/$token';
}

@override
Future<void> acceptInvite(String token) async {
  if (!isInviteTokenShapeValid(token)) {
    throw ArgumentError.value(token, 'token', 'Invalid invite token');
  }
  final userId = _client.auth.currentUser?.id;
  if (userId == null) throw StateError('Cannot accept invite without a signed-in user.');
  final tokenHash = hashInviteToken(token);
  final invite = await _client
      .from('household_invites')
      .select()
      .eq('token_hash', tokenHash)
      .eq('status', 'pending')
      .single();
  await _client.from('household_members').insert({
    'household_id': invite['household_id'],
    'user_id': userId,
    'role': 'member',
  });
  await _client.from('household_invites').update({
    'status': 'accepted',
    'accepted_by': userId,
    'accepted_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', invite['id']);
}
```

- [ ] **Step 4: Run invite tests**

Run:

```bash
cd apps/mobile
flutter test test/invite_token_test.dart
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit invite support**

Run:

```bash
git add apps/mobile/lib/household apps/mobile/lib/sync/remote_pantry_repository.dart apps/mobile/test/invite_token_test.dart
git diff --cached --check
git commit -m "feat(mobile): add household invites"
```

---

## Task 16: Add Household Settings UI

**Files:**
- Create: `apps/mobile/lib/widgets/settings/household_section.dart`
- Modify: `apps/mobile/lib/screens/settings_screen.dart`
- Create: `apps/mobile/test/household_section_test.dart`

- [ ] **Step 1: Write widget test**

Create `apps/mobile/test/household_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/widgets/settings/household_section.dart';

void main() {
  testWidgets('HouseholdSection renders members and invite action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: [
              HouseholdMember(
                householdId: 'household_1',
                userId: 'owner_1',
                role: 'owner',
                email: 'owner@example.com',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Kunish Kitchen'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('邀请成员'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Implement household section**

Create `apps/mobile/lib/widgets/settings/household_section.dart`:

```dart
import 'package:flutter/material.dart';

import '../../household/household_models.dart';
import '../../theme/app_spacing.dart';
import '../shared/fk_card.dart';
import '../shared/fk_section_head.dart';

class HouseholdSection extends StatelessWidget {
  const HouseholdSection({
    super.key,
    required this.householdName,
    required this.members,
    this.onInvite,
  });

  final String householdName;
  final List<HouseholdMember> members;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FkSectionHead(title: '家庭共享'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: FkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(householdName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                for (final member in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(member.email),
                    trailing: Text(member.role == 'owner' ? 'Owner' : 'Member'),
                  ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: onInvite,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('邀请成员'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add section to settings screen**

Modify `apps/mobile/lib/screens/settings_screen.dart` to include `HouseholdSection` above the backup section:

```dart
HouseholdSection(
  householdName: 'Kunish Kitchen',
  members: const [],
  onInvite: () {},
),
```

The following task wires real provider data. This step lands the component and placement.

- [ ] **Step 4: Run UI tests**

Run:

```bash
cd apps/mobile
flutter test test/household_section_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit settings section**

Run:

```bash
git add apps/mobile/lib/widgets/settings apps/mobile/lib/screens/settings_screen.dart apps/mobile/test/household_section_test.dart
git diff --cached --check
git commit -m "feat(mobile): add household settings section"
```

---

## Task 17: Wire Household Settings To Real State

**Files:**
- Modify: `apps/mobile/lib/widgets/settings/household_section.dart`
- Modify: `apps/mobile/lib/screens/settings_screen.dart`
- Modify: `apps/mobile/lib/household/household_session_controller.dart`
- Create: `apps/mobile/test/household_invite_widget_test.dart`

- [ ] **Step 1: Write invite dialog widget test**

Create `apps/mobile/test/household_invite_widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/settings/household_section.dart';

void main() {
  testWidgets('invite button opens email input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HouseholdSection(
            householdName: 'Kunish Kitchen',
            members: const [],
            onInviteEmail: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('邀请成员'));
    await tester.pumpAndSettle();

    expect(find.text('成员邮箱'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Extend HouseholdSection with invite email callback**

Modify constructor:

```dart
final Future<void> Function(String email)? onInviteEmail;
```

On invite button, open an `AlertDialog`:

```dart
Future<void> _showInviteDialog(BuildContext context) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('邀请成员'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: '成员邮箱'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            await onInviteEmail?.call(controller.text);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('发送邀请'),
        ),
      ],
    ),
  );
  controller.dispose();
}
```

- [ ] **Step 3: Add controller invite method**

In `HouseholdSessionController`:

```dart
Future<String> createInvite(String householdId, String email) {
  final gateway = _gateway;
  if (gateway is! HouseholdInviteGateway) {
    throw StateError('Household gateway does not support invites.');
  }
  return gateway.createInvite(householdId: householdId, email: email.trim());
}
```

Add interface:

```dart
abstract class HouseholdInviteGateway {
  Future<String> createInvite({
    required String householdId,
    required String email,
  });
}
```

Make `SupabaseHouseholdGateway` implement `HouseholdInviteGateway` by calling the invite methods already added to `SupabaseRemotePantryRepository`. Add a `RemotePantryRepository` constructor dependency to `SupabaseHouseholdGateway` and wire it in `householdGatewayProvider`.

- [ ] **Step 4: Run invite widget tests**

Run:

```bash
cd apps/mobile
flutter test test/household_invite_widget_test.dart
flutter test
flutter analyze
```

Expected: PASS and 0 analyzer issues.

- [ ] **Step 5: Commit real settings wiring**

Run:

```bash
git add apps/mobile/lib/widgets/settings apps/mobile/lib/screens/settings_screen.dart apps/mobile/lib/household apps/mobile/test/household_invite_widget_test.dart
git diff --cached --check
git commit -m "feat(mobile): wire household invite settings"
```

---

## Task 18: Add Documentation And Final Smoke Checks

**Files:**
- Modify: `README.md`
- Create: `apps/mobile/README.md`
- Create: `apps/api/README.md`
- Create: `supabase/README.md`

- [ ] **Step 1: Write root workflow docs**

Update `README.md` with:

```markdown
## Local Development

### Mobile

```bash
npm run mobile:pub-get
npm run mobile:analyze
npm run mobile:test
```

Run the app with Supabase configuration:

```bash
cd apps/mobile
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

### Supabase

```bash
supabase start
supabase db reset
supabase test db
```

### API

```bash
cd apps/api
npm install
npm test
npx wrangler deploy
```

The production Worker route is `api.fresh-pantry.kunish.eu.org`.
```

- [ ] **Step 2: Add mobile README**

Create `apps/mobile/README.md`:

```markdown
# Fresh Pantry Mobile

Flutter app for Fresh Pantry.

Required Dart defines for backend-enabled runs:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `FRESH_PANTRY_API_BASE_URL` defaults to `https://api.fresh-pantry.kunish.eu.org`

Validation:

```bash
flutter analyze
flutter test
```
```

- [ ] **Step 3: Add API README**

Create `apps/api/README.md`:

```markdown
# Fresh Pantry API

Cloudflare Worker for Fresh Pantry health checks and household invite links.

Routes:

- `GET /health`
- `GET /invite/:token`

Validation:

```bash
npm test
```
```

- [ ] **Step 4: Add Supabase README**

Create `supabase/README.md`:

```markdown
# Fresh Pantry Supabase

Supabase project files for family sharing.

Commands:

```bash
supabase start
supabase db reset
supabase test db
supabase status
```

Security rules:

- All shared tables have RLS enabled.
- Household data is visible only to `household_members`.
- Owner-only actions are household configuration, invites, and member removal.
```

- [ ] **Step 5: Run final validation**

Run:

```bash
npm run mobile:analyze
npm run mobile:test
npm run api:test
supabase db reset
supabase test db
git diff --check
```

Expected:

```text
All commands exit 0.
```

- [ ] **Step 6: Commit docs and final checks**

Run:

```bash
git add README.md apps/mobile/README.md apps/api/README.md supabase/README.md
git diff --cached --check
git commit -m "docs: document monorepo family sync workflows"
```

---

## Final Acceptance Criteria

- Root monorepo has `apps/mobile`, `apps/api`, and `supabase`.
- Flutter app still passes `flutter analyze` and `flutter test` from `apps/mobile`.
- Worker passes route tests and has `api.fresh-pantry.kunish.eu.org` in `wrangler.jsonc`.
- Supabase migrations create household, member, invite, shared data, sync event tables, RLS policies, indexes, and Realtime publication entries.
- RLS smoke tests prove owner/member/non-member boundaries.
- Mobile app can initialize Supabase from Dart defines.
- Mobile app has auth gate, household bootstrap, outbox persistence, merge policy, push coordinator, Realtime hooks, invite support, and household settings UI.
- AI settings, notification preferences, and caches remain local.
- No service-role key is required in Flutter or Worker code.
