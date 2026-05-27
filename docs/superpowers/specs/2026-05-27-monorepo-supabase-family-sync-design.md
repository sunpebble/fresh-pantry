# Monorepo Supabase Family Sync Design

Date: 2026-05-27
Status: Draft for written-spec review

## Goal

Convert Fresh Pantry into a standard monorepo and add first-phase backend support for household sharing.

The first phase must let the maintainer and family members share one household configuration and shared pantry data while preserving the app's local-first feel. Supabase is the shared data and auth backend. Cloudflare provides the stable project API domain at `api.fresh-pantry.kunish.eu.org`, but it does not proxy normal Supabase data access in this phase.

## Confirmed Decisions

- Scope option: connect the existing Flutter app to Supabase for login, household space, cloud sync, and family sharing.
- Auth model: each family member signs in with email magic link / OTP. The household owner invites members by email.
- Sync model: local-first with background bidirectional sync.
- Conflict model: merge operations and fields where possible; when the same field cannot be merged, latest edit wins and a visible sync-conflict record is kept.
- Shared data: inventory, shopping list, custom recipes, and household configuration.
- Personal local data: AI key/settings, notification preferences, food/recipe caches.
- Cloudflare domain: `api.fresh-pantry.kunish.eu.org`.
- Monorepo shape: standard monorepo with Flutter moved to `apps/mobile/`, Worker in `apps/api/`, and Supabase project in `supabase/`.
- Initial migration: when the first signed-in user creates a household, current local inventory, shopping list, and custom recipes are uploaded as the initial household data.
- Realtime: Supabase Realtime pushes household updates to other signed-in devices while the local outbox remains responsible for offline retry.

## Monorepo Structure

```text
fresh_pantry/
  apps/
    mobile/                # Existing Flutter app, moved intact
    api/                   # Cloudflare Worker
  supabase/
    migrations/            # SQL schema, RLS, indexes
    seed.sql               # Intentionally empty; tests own their fixtures
    config.toml            # Local Supabase CLI config
  docs/
    superpowers/
      specs/
      plans/
  README.md
  package.json             # Workspace scripts for api and supabase tasks
```

The Flutter move is structural, not a rewrite. Existing Riverpod providers, domain repos, widgets, tests, and platform directories move under `apps/mobile/`. Backend code and migrations live outside the Flutter package so future server work does not clutter the mobile project root.

## Runtime Architecture

Flutter talks directly to Supabase for:

- Auth and session state.
- Household and member queries.
- Inventory, shopping list, and custom recipe reads/writes.
- Realtime subscriptions.

The Cloudflare Worker handles:

- `GET /health` for deployment and domain checks.
- `GET /invite/:token` for invite landing and app deep-link redirects.
- A stable future API surface under `api.fresh-pantry.kunish.eu.org`.

The Worker is intentionally not a data gateway in phase one. Supabase already provides authenticated Postgres APIs, Realtime, and RLS. Keeping Flutter direct-to-Supabase avoids duplicating authorization logic in two places.

## Supabase Data Model

All shared tables include `id`, `household_id`, `created_at`, `updated_at`, `deleted_at`, and versioning fields where relevant.

### `profiles`

Stores user profile data linked to `auth.users`.

Key fields:

- `id uuid primary key references auth.users(id)`
- `email text`
- `display_name text`
- `created_at timestamptz`
- `updated_at timestamptz`

### `households`

Stores household-level configuration.

Key fields:

- `id uuid primary key`
- `name text not null`
- `owner_id uuid references auth.users(id)`
- `default_storage_area text`
- `category_preferences jsonb not null default '{}'`
- `unit_preferences jsonb not null default '{}'`
- `created_at timestamptz`
- `updated_at timestamptz`

### `household_members`

Connects users to households.

Key fields:

- `household_id uuid references households(id)`
- `user_id uuid references auth.users(id)`
- `role text check (role in ('owner', 'member'))`
- `joined_at timestamptz`

The primary key is `(household_id, user_id)`.

### `household_invites`

Tracks owner-created email invites.

Key fields:

- `id uuid primary key`
- `household_id uuid references households(id)`
- `email text not null`
- `token_hash text not null`
- `status text check (status in ('pending', 'accepted', 'expired', 'revoked'))`
- `expires_at timestamptz not null`
- `accepted_by uuid references auth.users(id)`
- `accepted_at timestamptz`

The raw token is never stored in the database.

### `inventory_items`

Represents shared pantry inventory using the existing `Ingredient` domain semantics.

Key fields:

- `id uuid primary key`
- `household_id uuid references households(id)`
- `name text not null`
- `quantity text not null`
- `unit text not null`
- `image_url text`
- `freshness_percent numeric`
- `state text`
- `expiry_label text`
- `category text`
- `barcode text`
- `storage text`
- `expiry_date timestamptz`
- `added_at timestamptz`
- `shelf_life_days integer`
- `version integer not null default 1`
- `client_id text`
- `client_updated_at timestamptz`
- `deleted_at timestamptz`

### `shopping_items`

Represents shared shopping list items.

Key fields:

- `id uuid primary key`
- `household_id uuid references households(id)`
- `name text not null`
- `detail text`
- `image_url text`
- `category text`
- `is_checked boolean not null default false`
- `version integer not null default 1`
- `client_id text`
- `client_updated_at timestamptz`
- `deleted_at timestamptz`

### `custom_recipes`

Stores user-created recipes that are shared by the household.

The first migration preserves the existing `Recipe.toJson()` shape in a `payload jsonb` column. This keeps phase-one migration focused on sync and sharing, not recipe schema normalization.

Key fields:

- `id uuid primary key`
- `household_id uuid references households(id)`
- `payload jsonb not null`
- `version integer not null default 1`
- `client_id text`
- `client_updated_at timestamptz`
- `deleted_at timestamptz`

### `sync_events`

Records client operations for push/pull, conflict investigation, and incremental sync.

Key fields:

- `id uuid primary key`
- `household_id uuid references households(id)`
- `entity_type text check (entity_type in ('inventory_item', 'shopping_item', 'custom_recipe', 'household_config'))`
- `entity_id uuid not null`
- `operation text not null`
- `patch jsonb not null default '{}'`
- `base_version integer`
- `result_version integer`
- `client_id text not null`
- `created_by uuid references auth.users(id)`
- `created_at timestamptz not null default now()`

## RLS And Authorization

Every shared table in the exposed schema must have RLS enabled.

Core policy rule:

- A user can read or write a household row only when `(household_id, auth.uid())` exists in `household_members`.

Role-specific rules:

- `owner` can update household configuration.
- `owner` can create, revoke, and inspect invites for their household.
- `owner` can remove `member` rows.
- `member` can read household configuration and read/write shared inventory, shopping list, and custom recipes.
- Non-members cannot read shared rows even if they are authenticated.

Policies must use `TO authenticated` plus explicit household membership predicates. `TO authenticated` by itself is not enough authorization. Client code only receives the Supabase publishable key; service-role credentials stay out of the Flutter app and out of the repository.

## Flutter Design

The existing local persistence boundary remains the center of the mobile app:

```text
Riverpod notifier -> domain repo -> StorageAdapter -> SharedPreferences
```

Phase one adds sync beside this boundary:

```text
UI action
  -> Riverpod notifier
  -> local domain repo
  -> SyncOutboxRepo
  -> SyncCoordinator
  -> RemotePantryRepository
  -> Supabase
```

### New Mobile Components

`RemotePantryRepository`

- Wraps Supabase Auth, household queries, shared CRUD, invite acceptance, and Realtime streams.
- Exposes typed methods rather than letting screens call Supabase directly.

`SyncOutboxRepo`

- Persists pending local operations through the existing `StorageAdapter` boundary.
- Tracks operation id, entity type, entity id, patch, base version, client id, and retry metadata.

`SyncCoordinator`

- Pushes outbox entries to Supabase.
- Pulls remote changes since the last sync cursor.
- Applies Realtime events to local repos.
- Runs merge logic and records conflicts.
- Exposes sync state for UI.

`HouseholdSessionController`

- Owns sign-in state, selected household, first-household bootstrap, and invite acceptance.

### App Flows

Sign in:

1. User enters email.
2. Supabase sends OTP / magic link.
3. App listens to auth state and loads household membership.

Create household:

1. Signed-in user with no household creates a household.
2. App uploads current local inventory, shopping list, and custom recipes as initial household data.
3. App records sync cursors and enables Realtime.

Accept invite:

1. User opens `https://api.fresh-pantry.kunish.eu.org/invite/:token`.
2. Worker redirects to the app deep link when possible.
3. App signs the user in if needed.
4. App accepts the invite and joins the household.

Normal edit:

1. User edits local data.
2. UI updates immediately.
3. App writes an outbox operation.
4. SyncCoordinator uploads when online and authenticated.
5. Other devices receive Realtime updates and merge locally.

## Conflict Handling

Records use stable ids and versions. Client operations include a base version whenever possible.

Merge order:

1. If the remote row has not changed since `base_version`, apply the local operation.
2. If different fields changed, merge field-by-field.
3. If the operation is quantity-like or action-like, prefer operation semantics such as intake, deduction, and checked-toggle over whole-row overwrite.
4. If the same field changed incompatibly, apply the latest `client_updated_at` / server `updated_at` value and create a local sync-conflict record.
5. If a row was soft-deleted remotely, do not resurrect it from stale offline state unless the local operation is a deliberate restore operation.

Conflicts are visible but lightweight in phase one. The UI should show a sync status entry in settings and preserve enough metadata for troubleshooting. A full conflict review center is out of scope.

## Cloudflare Worker Design

Worker app lives in `apps/api/`.

Routes:

- `GET /health`
  - Returns JSON with service name, environment, and current timestamp.
- `GET /invite/:token`
  - Validates token shape.
  - Redirects to the mobile deep link.
  - Provides an HTML fallback if the app is not installed.

Deployment target:

- Route/custom domain: `api.fresh-pantry.kunish.eu.org`.

Secrets:

- If the Worker needs to validate invite metadata in a later phase, Supabase URL and publishable key can be stored as Wrangler secrets.
- No service-role key is required for phase-one Worker routes.

## Migration And Delivery Plan

Implementation should be split into these stages:

1. Move the repository into monorepo shape and restore Flutter tests.
2. Add Supabase project files, migrations, RLS, and local development docs.
3. Add Supabase Flutter initialization and email OTP sign-in.
4. Add household creation and initial local-data upload.
5. Add outbox, push/pull, sync cursors, and merge logic.
6. Add Realtime subscriptions for shared household data.
7. Add invite creation, Worker invite route, and mobile invite acceptance.
8. Add settings UI for household members, role display, invites, and sync status.
9. Configure deployment scripts and document `api.fresh-pantry.kunish.eu.org`.

Each stage should leave the mobile app runnable. The monorepo move is a mechanical stage by itself so later functional diffs are easier to review.

## Testing Strategy

Flutter:

- Keep `flutter analyze` and `flutter test` green after the monorepo move.
- Add unit tests for `SyncCoordinator`, `SyncOutboxRepo`, merge rules, bootstrap upload, and deleted-row behavior.
- Add widget tests for login gate, household setup, invite acceptance, and settings household controls.

Supabase:

- Test migrations locally.
- Add SQL tests or scripted checks for RLS:
  - owner can manage household and invites.
  - member can read/write shared pantry data.
  - non-member cannot read shared rows.
  - authenticated user without membership cannot access another household.

Worker:

- Test `/health`.
- Test `/invite/:token` redirect and invalid-token fallback.

Smoke:

- Two test users join one household.
- User A edits a shopping item.
- User B receives the update through Realtime.
- User A edits offline, reconnects, and the outbox upload is applied.

## Out Of Scope

- Web management UI.
- Worker as data gateway for all Supabase traffic.
- Full conflict review center.
- Shared AI keys or AI settings.
- Shared notification preferences.
- Remote push notification scheduling.
- Recipe schema normalization beyond what sync requires.
- Splitting Flutter domain models into shared packages.

## Risks And Mitigations

- Monorepo move can break Flutter tooling. Mitigate by doing it as the first isolated stage and running the full Flutter baseline before functional changes.
- Local-first sync can create subtle conflicts. Mitigate by starting with a small set of explicit operations, stable ids, soft deletes, and focused merge tests.
- RLS mistakes can expose household data. Mitigate with RLS tests and membership predicates on every shared table.
- Realtime can reconnect or replay events. Mitigate with idempotent event application and version checks.
- Existing local models lack remote identity fields. Mitigate with additive model fields and migration tests rather than replacing current storage at once.
