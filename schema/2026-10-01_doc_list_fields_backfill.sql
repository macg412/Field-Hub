-- ───────────────────────────────────────────────────────────────────────────
-- Backfill list_name / list_date for the existing rows.
-- Run AFTER 2026-10-01_doc_list_fields.sql.
--
-- Hazard: documents_updated_at is an unconditional BEFORE UPDATE trigger
-- (NEW.updated_at = now()). A plain UPDATE would stamp every row as "edited
-- just now", wrecking the folder sort order and every "edited X ago" label.
--
-- `set local session_replication_role = replica` suppresses user triggers for
-- this transaction only, and reverts on commit -- so it cannot leak through a
-- pooled connection. Unlike ALTER TABLE ... DISABLE TRIGGER it takes no
-- ACCESS EXCLUSIVE lock, so the UPDATE holds only ROW EXCLUSIVE and readers
-- are never blocked. Field users see nothing.
--
-- Replica mode also suppresses FK constraint triggers, which is harmless here:
-- this statement writes only list_name / list_date / list_backfill_done and
-- never touches job_id or site_id.
--
-- The payload column is never assigned, so its TOAST pointers are reused:
-- 519 MB is NOT rewritten or duplicated. New heap is ~1 MB.
--
-- Measured: 25 rows / ~28 MB of payload per batch ~= 2.5 s (~10 MB/s detoast).
--
-- Run this repeatedly until it reports 0 rows. Each run is its own
-- transaction, idempotent, and resumable if interrupted.
-- ───────────────────────────────────────────────────────────────────────────

begin;
set local session_replication_role = replica;

with batch as (
  select id from public.documents
  where not list_backfill_done
  order by id
  limit 25
)
update public.documents d
set list_name = coalesce(
      nullif(btrim(d.payload->>'tplName'), ''),
      nullif(btrim(d.payload->>'jobName'), '')
    ),
    list_date = coalesce(
      nullif(btrim(d.payload->>'jobDate'), ''),
      nullif(btrim(d.payload->>'date'), '')
    ),
    list_backfill_done = true
from batch
where d.id = batch.id;

commit;

-- Progress. Repeat the above while remaining > 0.
--   select count(*) filter (where not list_backfill_done) as remaining,
--          pg_size_pretty(sum(pg_column_size(payload))
--            filter (where not list_backfill_done)::bigint) as bytes_remaining
--   from public.documents;

-- Verify, using the same falsy semantics the app's `||` chains use. Expect 0 / 0.
--   select
--     count(*) filter (where list_name is distinct from coalesce(
--       nullif(btrim(payload->>'tplName'),''), nullif(btrim(payload->>'jobName'),''))) as name_mismatches,
--     count(*) filter (where list_date is distinct from coalesce(
--       nullif(btrim(payload->>'jobDate'),''), nullif(btrim(payload->>'date'),''))) as date_mismatches
--   from public.documents;

-- Confirm no row was touched by documents_updated_at. Should still predate the
-- backfill (was 2026-10-01 02:44:22.982005+00 before step 1).
--   select max(updated_at) from public.documents;

-- Only once the above is clean AND the frontend change is deployed, retire the
-- marker column (metadata-only, instant):
--   alter table public.documents drop column list_backfill_done;
