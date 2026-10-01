-- ───────────────────────────────────────────────────────────────────────────
-- Move base64 photos out of documents.payload into the doc-photos bucket.
--
-- The byte-moving half runs in the migrate-doc-photos Edge Function, because
-- Postgres cannot upload to Storage. Enabling the `http` extension would make it
-- possible but permanently widens the database's security surface, so it was not
-- installed. Running in an Edge Function also keeps the image data inside
-- Supabase's network instead of pulling ~900 MB through a developer connection.
--
-- This file holds the SQL side of that migration, applied as:
--   doc_photo_migration_scaffold
--   updated_at_opt_out_guc
--   next_photo_migration_batch
--   doc_photo_migration_grants
-- ───────────────────────────────────────────────────────────────────────────

-- Audit + progress, one row per document. photos maps a payload path
-- ("photoBefore.0", "photoPages.2") to the public URL it became.
create table if not exists public.doc_photo_migration (
  doc_id          uuid primary key references public.documents(id) on delete cascade,
  photos          jsonb       not null,
  photo_count     int         not null,
  bytes_uploaded  bigint      not null,
  payload_before  bigint      not null,
  uploaded_at     timestamptz not null default now(),
  rewritten_at    timestamptz
);
grant select, insert, update, delete on public.doc_photo_migration to service_role;
revoke all on public.doc_photo_migration from anon, authenticated;

-- update_updated_at backs documents_updated_at and jobs_updated_at and stamps
-- NEW.updated_at = now() unconditionally. Right for app writes, wrong for a
-- maintenance rewrite that touches every row: it would restamp all 436 documents
-- as "edited just now" and wreck folder ordering and the "edited X ago" labels.
--
-- session_replication_role would disable the trigger outright but is superuser-
-- gated and NOT reachable from a SECURITY DEFINER function (verified: "permission
-- denied to set parameter"). app.* GUCs are user-definable, so any role can opt
-- out for the length of its own transaction.
--
-- Backward compatible: unset (the normal case) behaves exactly as before.
create or replace function public.update_updated_at()
returns trigger language plpgsql as $$
BEGIN
  IF coalesce(current_setting('app.skip_updated_at', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Deliberately narrow: only ever writes payload, for one id.
create or replace function public.migrate_doc_payload(p_doc_id uuid, p_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.skip_updated_at', 'on', true);  -- transaction-local
  update public.documents set payload = p_payload where id = p_doc_id;
end;
$$;
revoke all on function public.migrate_doc_payload(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.migrate_doc_payload(uuid, jsonb) to service_role;

-- Next ids to process. Deliberately does NOT reference payload: ordering or
-- filtering on pg_column_size(payload) would detoast all 519 MB on every call.
create or replace function public.next_photo_migration_batch(p_limit int)
returns setof uuid language sql stable security definer set search_path = public as $$
  select d.id
  from public.documents d
  left join public.doc_photo_migration m on m.doc_id = d.id
  where m.doc_id is null
  order by d.id
  limit greatest(1, least(p_limit, 25))
$$;
revoke all on function public.next_photo_migration_batch(int) from public, anon, authenticated;
grant execute on function public.next_photo_migration_batch(int) to service_role;

-- ── After the sweep reports remaining = 0 ──
-- Only signatureData should still be inline (~34 kB each, ~1% of the total, left
-- deliberately):
--   select count(*) filter (where payload::text like '%data:image%') as rows_with_base64,
--          count(*) filter (where payload::text like '%"signatureData": "data:image%') as signatures
--   from public.documents;
--
-- Confirm no document was restamped (should predate the migration):
--   select max(updated_at) from public.documents;
--
-- Then reclaim the disk. Safe to run FULL only now that the table is small --
-- before the migration it would have rewritten 570 MB under ACCESS EXCLUSIVE:
--   vacuum (full, analyze) public.documents;
--
-- Finally delete the Edge Function: it is guarded by a token baked into its source
-- but is still invokable with the public anon key, and it has no further purpose.

-- ───────────────────────────────────────────────────────────────────────────
-- 2026-10-02 — applied as drop_photo_migration_helpers
--
-- Migration complete: 436 documents, 878 photos, 0 failures.
--   live payload   519 MB -> 6,357 kB
--   documents      570 MB -> 7,064 kB (after vacuum full, 0 dead tuples)
--   doc-photos     891 objects, 386 MB
--   max(updated_at) unchanged at 2026-10-01 02:44:22.982005+00
--
-- The one-shot helpers are dropped. migrate_doc_payload in particular could
-- rewrite any document's payload while suppressing updated_at, which is not a
-- capability worth leaving in place. Both had zero dependents and backed no
-- triggers. Their definitions remain above if ever needed again.
drop function if exists public.migrate_doc_payload(uuid, jsonb);
drop function if exists public.next_photo_migration_batch(int);

-- Deliberately KEPT:
--  * update_updated_at and its app.skip_updated_at opt-out — still backs
--    documents_updated_at and jobs_updated_at (verified: 2 triggers still wired,
--    and a normal write still stamps updated_at). Inert unless the GUC is set.
--  * doc_photo_migration — the audit trail of which payload path became which URL.
--
-- The migrate-doc-photos Edge Function body was replaced with a 410 stub; the slug
-- itself still needs deleting, as the MCP server exposes no delete operation:
--   supabase functions delete migrate-doc-photos --project-ref idvodclpwdabfgsqniwl
