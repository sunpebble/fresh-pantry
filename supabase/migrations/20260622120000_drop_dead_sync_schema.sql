-- Drop dead sync schema confirmed by the 2026-06-22 audit: these have
-- zero client traffic and no DB-side dependents (no FK / view / function / trigger
-- references them). Done as a NEW migration — the prior files are an append-only
-- ledger that must stay byte-aligned with prod schema_migrations.
--
--   * public.sync_events — an event-log table created in the initial schema
--     (20260527071301) but NEVER read or written by the SwiftUI client. Sync runs
--     through the per-entity tables + the client outbox, not a server event log
--     (see the NOTE in 20260607120000_meal_plan_entries_sync.sql). Its index,
--     GRANT, RLS policies, CHECK constraint, and supabase_realtime publication
--     membership all drop with the table.
--   * households.category_preferences / unit_preferences — jsonb columns the
--     client explicitly ignores (the iOS DietPreferenceStore stores dietary
--     labels in UserDefaults, and household-synced dietary prefs flow through
--     public.dietary_preferences; unit_preferences was never wired). No RLS /
--     RPC / trigger references either column.
--
-- No CASCADE on purpose: nothing depends on these, so a plain DROP fails loudly
-- if that assumption is ever wrong rather than silently dropping a dependent.

drop table if exists public.sync_events;

alter table public.households
  drop column if exists category_preferences,
  drop column if exists unit_preferences;
