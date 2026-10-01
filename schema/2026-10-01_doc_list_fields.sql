-- ───────────────────────────────────────────────────────────────────────────
-- Stop the folder list from detoasting payload.
--
-- DOC_CARD_COLS excludes `payload`, but projects payload->>'tplName' etc.
-- A jsonb operator forces Postgres to detoast the WHOLE column, so opening a
-- job folder reads every photo in it. Measured on job 2938bc32 (59 docs):
--
--   with the payload->> projections : 28,663 buffers (~224 MB), 4,389 ms
--   without them                    :        28 buffers,            1.6 ms
--
-- This migration moves those four display fields into plain columns.
-- Step 1 here is DDL only. The backfill is a separate file (…_backfill.sql)
-- because it must run in bounded batches.
-- ───────────────────────────────────────────────────────────────────────────

-- 1. Columns. Nullable text, no default -> metadata-only in PG17.
--    Instant, no table rewrite, no long lock. The 519 MB of TOAST is untouched.
--    text (not date) so fmtDate() receives byte-identical values to today.
alter table public.documents
  add column if not exists list_name text,
  add column if not exists list_date text;

-- 2. Resumable-backfill marker. Constant default -> also metadata-only.
--    Dropped again at the end of the backfill.
alter table public.documents
  add column if not exists list_backfill_done boolean not null default false;

comment on column public.documents.list_name is
  'Display name for the folder list. Mirrors payload tplName/jobName so the list query never detoasts payload. Maintained by documents_sync_list_fields.';
comment on column public.documents.list_date is
  'Display date for the folder list. Mirrors payload jobDate/date. Text, not date, to match the previous payload->> output exactly.';

-- 3. Keep them in sync on every write.
--    coalesce(nullif(btrim(x),'')) replicates the JS `||` chain exactly:
--    there are 2 rows with tplName = '', 1 with jobName = '', 1 with
--    jobDate = ''. Plain coalesce would return '' and render a blank card
--    where the app currently falls through to `title`.
create or replace function public.documents_sync_list_fields()
returns trigger
language plpgsql
as $$
begin
  new.list_name := coalesce(
    nullif(btrim(new.payload->>'tplName'), ''),   -- asbuilt / fieldforms
    nullif(btrim(new.payload->>'jobName'), '')    -- scoping
  );
  new.list_date := coalesce(
    nullif(btrim(new.payload->>'jobDate'), ''),   -- jobcard
    nullif(btrim(new.payload->>'date'), '')       -- storeman
  );
  return new;
end;
$$;

drop trigger if exists documents_sync_list_fields on public.documents;
create trigger documents_sync_list_fields
  before insert or update of payload on public.documents
  for each row execute function public.documents_sync_list_fields();
