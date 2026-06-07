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

## JSON column migration (completed 2026-06-07)

### documents.payload
- 28 of 42 documents have payload (matches Tokyo exactly)
- 14 documents have NULL payload (same as Tokyo — never populated)
- All 28 transferred; large documents handled as follows:
  - Small (<10KB): full payload transferred verbatim
  - Forms with large photoPages/inlinePhotos (up to 19MB): fieldVals + tplId + tplName + drawData preserved; photoPages/inlinePhotos cleared to []
  - Jobcards with signatureData (base64 PNG): all text fields preserved; signatureData/photoAdd/photoBefore/photoAfter stripped

### forms JSON columns
- field_vals, draw_data, photo_pages: fully transferred for both rows
- inline_photos: ba241f4b had 2.1MB embedded photos — cleared to []; d145a133 had [] (already empty)

## Storage migration (completed 2026-06-07)

### Buckets created on Sydney
- site-photos (public, 10MB)
- job-pdfs (public, 20MB)
- form-templates (public, 20MB, PDF only)
- form-exports (private)

### Files transferred: 72 total, 0 failures
- form-templates: 13 PDFs
- job-pdfs: 16 PDFs (up to 15.9MB)
- site-photos: 43 JPGs

### Post-transfer
- documents.pdf_url: 14 URLs rewritten from rgcmisfwrflshggcwjie → idvodclpwdabfgsqniwl

## Auth user migration (completed 2026-06-07)

8 users inserted into auth.users on Sydney with bcrypt hashes preserved.
session_replication_role = replica used to suppress on_auth_user_created trigger
(profiles already exist and are correctly joined via FK).

| Email | Confirmed | Admin |
|---|---|---|
| ben.macgeorge@downer.co.nz | yes | yes |
| benmacgeorge93@gmail.com | yes | no |
| gunn.pax.bellum@gmail.com | no | no |
| ben.edwards@downer.co.nz | yes | no |
| ross.mcmillan@downer.co.nz | yes | no |
| alex.king1@downer.co.nz | yes | no |
| troy.evans@downer.co.nz | yes | no |
| hamish.mcmillan@downer.co.nz | yes | no |

All users can log in with their existing passwords unchanged.
