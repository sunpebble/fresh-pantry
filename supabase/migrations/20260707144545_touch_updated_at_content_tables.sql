-- Attach app_private.touch_updated_at (20260615100000) to the seven synced
-- content tables. They only had bump_row_version, so an UPDATE (edit, soft-delete
-- tombstone) never moved `updated_at` past the INSERT default — the client's
-- incremental pull (`updated_at >= since`) silently skipped every update.
-- INSERTs keep the column default now(); the trigger is UPDATE-only, matching
-- the profiles_touch_updated_at precedent. Re-pulling at the gte boundary is
-- idempotent (merge policy converges), so no backfill is needed.
--
-- ROLLOUT ORDER: apply this migration BEFORE shipping any client build that
-- contains the SyncCursor.stampUpdatedAt fix. A fixed client against an
-- un-migrated database persists a working cursor whose delta pulls then miss
-- every UPDATE — strictly worse than the old always-full-pull behavior.
-- Rolling back this trigger is likewise incompatible with released clients.

drop trigger if exists inventory_items_touch_updated_at on public.inventory_items;
create trigger inventory_items_touch_updated_at
  before update on public.inventory_items
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists shopping_items_touch_updated_at on public.shopping_items;
create trigger shopping_items_touch_updated_at
  before update on public.shopping_items
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists custom_recipes_touch_updated_at on public.custom_recipes;
create trigger custom_recipes_touch_updated_at
  before update on public.custom_recipes
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists meal_plan_entries_touch_updated_at on public.meal_plan_entries;
create trigger meal_plan_entries_touch_updated_at
  before update on public.meal_plan_entries
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists food_log_entries_touch_updated_at on public.food_log_entries;
create trigger food_log_entries_touch_updated_at
  before update on public.food_log_entries
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists favorite_recipes_touch_updated_at on public.favorite_recipes;
create trigger favorite_recipes_touch_updated_at
  before update on public.favorite_recipes
  for each row
  execute function app_private.touch_updated_at();

drop trigger if exists dietary_preferences_touch_updated_at on public.dietary_preferences;
create trigger dietary_preferences_touch_updated_at
  before update on public.dietary_preferences
  for each row
  execute function app_private.touch_updated_at();
