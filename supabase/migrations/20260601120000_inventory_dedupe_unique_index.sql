-- Defense-in-depth against duplicate inventory rows from any client (including
-- old binaries that re-mint a fresh uuid for the same logical item on each sync
-- bootstrap, see _withInventorySyncIds + uploadInitialData on the client).
--
-- Every inventory write goes through upsert(ignoreDuplicates: true) =
-- `ON CONFLICT DO NOTHING`, or a plain update-by-id (RemotePantryRepository),
-- so a colliding insert is silently skipped instead of erroring. A logical
-- inventory item is uniquely identified by (household_id, name, added_at) — the
-- clone bug always preserved the original added_at — so this index collapses
-- those duplicates at the source of truth without touching the happy path.
--
-- Partial on `deleted_at IS NULL` so tombstoned rows never block a legitimate
-- re-add of the same item later.
create unique index if not exists inventory_items_household_name_added_uniq
  on public.inventory_items (household_id, name, added_at)
  where deleted_at is null;
