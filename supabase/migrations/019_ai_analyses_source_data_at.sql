-- ============================================================
-- Migration: makes sure ai_analyses.source_data_at actually exists.
--
-- Root cause of "تحلیل هوشمند never saves, every visit regenerates it":
-- the analyze-project Edge Function's insert into ai_analyses was failing
-- every single time with "Could not find the 'source_data_at' column of
-- 'ai_analyses' in the schema cache" — PostgREST's classic error for a
-- column its cached schema doesn't know about. `create table if not
-- exists` in migration 015 is a no-op against a table that already
-- exists with an older/incomplete shape, so if ai_analyses was ever
-- created before source_data_at was added to that migration, re-running
-- 015 silently never adds the missing column.
--
-- Nullable here (not `not null` like migration 015's original intent):
-- ADD COLUMN ... NOT NULL would fail outright against any existing rows
-- with no value to backfill, and the column is always supplied by the
-- Edge Function on insert anyway, so relaxing it costs nothing in
-- practice while making this migration safe to run unconditionally.
--
-- `notify pgrst, 'reload schema'` asks PostgREST to pick up the change
-- immediately instead of waiting for its next periodic refresh — the
-- same fix as the Dashboard's Settings → API → "Reload schema" button.
-- ============================================================

alter table ai_analyses add column if not exists source_data_at timestamptz;

notify pgrst, 'reload schema';
