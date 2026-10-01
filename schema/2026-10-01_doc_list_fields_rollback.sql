-- Full rollback. Safe at any point: the old app code path
-- (payload->>'tplName' …) keeps working because payload was never modified.
drop trigger if exists documents_sync_list_fields on public.documents;
drop function if exists public.documents_sync_list_fields();
alter table public.documents
  drop column if exists list_name,
  drop column if exists list_date,
  drop column if exists list_backfill_done;
