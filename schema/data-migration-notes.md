# Data Migration Notes — Tokyo → Sydney

**Date:** 2026-06-07  
**Source:** Tokyo project `rgcmisfwrflshggcwjie`  
**Target:** Sydney project `idvodclpwdabfgsqniwl`

## Row counts (verified)

| Table | Rows |
|---|---|
| profiles | 8 |
| jobs | 13 |
| sites | 20 |
| documents | 42 |
| forms | 2 |
| form_templates | 32 |
| site_photos | 37 |
| activity_log | 255 |

## Migrations applied to Sydney

| # | Name |
|---|---|
| 01 | `01_tables_indexes_triggers` — full schema |
| 02 | `02_functions_and_rls` — is_approved, is_admin, all RLS policies |
| 03 | `03_data_profiles_jobs_sites_templates_photos` |
| 04 | `04_data_documents_forms` |
| 05 | `05_data_activity_log_batch1` (rows 1–85) |
| 06 | `06_data_activity_log_batch2` (rows 86–170) |
| 07 | `07_data_activity_log_batch3` (rows 171–255) |

## Pending

- **`documents.payload`** (JSONB) — omitted due to size; needs UPDATE pass from Tokyo
- **`forms` JSON columns** (`field_vals`, `draw_data`, `inline_photos`, `photo_pages`) — omitted; needs UPDATE pass
- **Storage buckets** — not yet created on Sydney; site-photos, job-pdfs, form-templates, form-exports buckets need creating
- **Storage objects** — photo and PDF files need copying from Tokyo to Sydney buckets
- **Auth users** — 8 users need migrating via Supabase auth admin API (cannot be done via SQL)
- **App config** — SUPABASE_URL + anon key in Login-Page and Field-Hub repos need updating
- **`site_photos.public_url`** — currently points to Sydney URL already (rewritten during migration); will be correct once storage objects are copied
- **`documents.pdf_url`** — still points to Tokyo URLs; update after job-pdfs bucket is populated
