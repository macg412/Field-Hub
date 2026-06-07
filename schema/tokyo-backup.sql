-- ============================================================
-- Bamvalley schema backup — Tokyo project (rgcmisfwrflshggcwjie)
-- Exported 2026-06-07
-- Target for migration: Sydney project (idvodclpwdabfgsqniwl)
-- ============================================================

-- Extension required for uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ============================================================
-- FUNCTIONS (before tables that reference them via triggers)
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_approved()
  RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (SELECT auth.uid())
      AND approved = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
  RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (SELECT auth.uid())
      AND is_admin = true
      AND approved = true
  );
$$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
  RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at()
  RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- Fires on auth.users INSERT; creates the matching profiles row.
-- First user registered is auto-approved and made admin.
CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  is_first boolean;
BEGIN
  SELECT COUNT(*) = 0 INTO is_first FROM public.profiles;
  INSERT INTO public.profiles (id, name, email, is_admin, approved)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NEW.email,
    is_first,
    is_first
  );
  RETURN NEW;
END;
$$;


-- ============================================================
-- TABLES  (in FK dependency order)
-- ============================================================

CREATE TABLE public.profiles (
  id            uuid        NOT NULL,
  name          text        NOT NULL,
  email         text        NOT NULL,
  is_admin      bool        NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  approved      bool        NOT NULL DEFAULT false,
  CONSTRAINT profiles_pkey   PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE TABLE public.jobs (
  id               uuid        NOT NULL DEFAULT uuid_generate_v4(),
  wo_number        text        NOT NULL,
  job_name         text        NOT NULL,
  created_by       uuid,
  created_by_name  text        NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  address          text,
  job_type         text,
  status           text                 DEFAULT 'active',
  scheduled_date   date,
  cae_number       text,
  notes            text,
  updated_by_name  text,
  description      text,
  je_number        text,
  ele_number       text,
  downer_wo_number text,
  first_responder  text,
  second_responder text,
  downer_pm        text,
  powerco_pm       text,
  CONSTRAINT jobs_pkey           PRIMARY KEY (id),
  CONSTRAINT jobs_wo_key         UNIQUE (wo_number),
  CONSTRAINT jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);

CREATE TABLE public.sites (
  id              uuid        NOT NULL DEFAULT uuid_generate_v4(),
  job_id          uuid        NOT NULL,
  name            text        NOT NULL,
  created_by      uuid        NOT NULL,
  created_by_name text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  sort_order      int4        NOT NULL DEFAULT 0,
  CONSTRAINT sites_pkey            PRIMARY KEY (id),
  CONSTRAINT sites_job_id_fkey     FOREIGN KEY (job_id)     REFERENCES public.jobs(id)     ON DELETE CASCADE,
  CONSTRAINT sites_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);

CREATE TABLE public.documents (
  id               uuid        NOT NULL DEFAULT uuid_generate_v4(),
  job_id           uuid        NOT NULL,
  doc_type         text        NOT NULL,
  title            text,
  created_by_name  text,
  updated_by_name  text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid,
  site_id          uuid,
  payload          jsonb,
  pdf_url          text,
  submitted        bool                 DEFAULT false,
  CONSTRAINT documents_pkey            PRIMARY KEY (id),
  CONSTRAINT documents_job_id_fkey     FOREIGN KEY (job_id)    REFERENCES public.jobs(id)     ON DELETE CASCADE,
  CONSTRAINT documents_site_id_fkey    FOREIGN KEY (site_id)   REFERENCES public.sites(id)    ON DELETE SET NULL,
  CONSTRAINT documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id)
);

CREATE TABLE public.activity_log (
  id         uuid        NOT NULL DEFAULT uuid_generate_v4(),
  job_id     uuid,
  doc_id     uuid,
  action     text        NOT NULL,
  summary    text,
  actor_name text,
  at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_log_pkey         PRIMARY KEY (id),
  CONSTRAINT activity_log_job_id_fkey  FOREIGN KEY (job_id) REFERENCES public.jobs(id)      ON DELETE CASCADE,
  CONSTRAINT activity_log_doc_id_fkey  FOREIGN KEY (doc_id) REFERENCES public.documents(id) ON DELETE SET NULL
);

CREATE TABLE public.form_templates (
  id           text        NOT NULL,
  name         text        NOT NULL,
  description  text,
  category     text        NOT NULL DEFAULT 'general',
  storage_path text,
  version      text,
  sort_order   int4        NOT NULL DEFAULT 0,
  is_active    bool        NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT form_templates_pkey PRIMARY KEY (id)
);

CREATE TABLE public.forms (
  id              uuid        NOT NULL DEFAULT uuid_generate_v4(),
  job_id          uuid        NOT NULL,
  site_id         uuid        NOT NULL,
  category        text        NOT NULL,
  template_id     text        NOT NULL,
  template_name   text        NOT NULL,
  status          text        NOT NULL DEFAULT 'draft',
  field_vals      jsonb       NOT NULL DEFAULT '{}',
  draw_data       jsonb       NOT NULL DEFAULT '{}',
  inline_photos   jsonb       NOT NULL DEFAULT '[]',
  photo_pages     jsonb       NOT NULL DEFAULT '[]',
  created_by      uuid        NOT NULL,
  created_by_name text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT forms_pkey            PRIMARY KEY (id),
  CONSTRAINT forms_job_id_fkey     FOREIGN KEY (job_id)     REFERENCES public.jobs(id)     ON DELETE CASCADE,
  CONSTRAINT forms_site_id_fkey    FOREIGN KEY (site_id)    REFERENCES public.sites(id)    ON DELETE CASCADE,
  CONSTRAINT forms_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id)
);

CREATE TABLE public.site_photos (
  id              uuid        NOT NULL DEFAULT uuid_generate_v4(),
  job_id          uuid        NOT NULL,
  site_id         uuid        NOT NULL,
  storage_path    text        NOT NULL,
  public_url      text,
  caption         text        NOT NULL DEFAULT '',
  notes           text        NOT NULL DEFAULT '',
  sort_order      int4        NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by_name text        NOT NULL DEFAULT '',
  CONSTRAINT site_photos_pkey          PRIMARY KEY (id),
  CONSTRAINT site_photos_job_id_fkey   FOREIGN KEY (job_id)  REFERENCES public.jobs(id)  ON DELETE CASCADE,
  CONSTRAINT site_photos_site_id_fkey  FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE
);


-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX activity_log_doc_id_idx  ON public.activity_log  USING btree (doc_id);
CREATE INDEX activity_log_job_id_idx  ON public.activity_log  USING btree (job_id);
CREATE INDEX documents_created_by_idx ON public.documents     USING btree (created_by);
CREATE INDEX documents_job_id_idx     ON public.documents     USING btree (job_id);
CREATE INDEX documents_site_id_idx    ON public.documents     USING btree (site_id);
CREATE INDEX forms_created_by_idx     ON public.forms         USING btree (created_by);
CREATE INDEX forms_job_id_idx         ON public.forms         USING btree (job_id);
CREATE INDEX forms_site_id_idx        ON public.forms         USING btree (site_id);
CREATE INDEX forms_updated_at_idx     ON public.forms         USING btree (updated_at DESC);
CREATE INDEX jobs_created_at_idx      ON public.jobs          USING btree (created_at DESC);
CREATE INDEX jobs_created_by_idx      ON public.jobs          USING btree (created_by);
CREATE INDEX jobs_wo_idx              ON public.jobs          USING btree (wo_number);
CREATE INDEX site_photos_job_id_idx   ON public.site_photos   USING btree (job_id);
CREATE INDEX site_photos_site_id_idx  ON public.site_photos   USING btree (site_id);
CREATE INDEX sites_created_by_idx     ON public.sites         USING btree (created_by);
CREATE INDEX sites_job_id_idx         ON public.sites         USING btree (job_id);


-- ============================================================
-- TRIGGERS
-- ============================================================

CREATE TRIGGER documents_updated_at
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER forms_updated_at
  BEFORE UPDATE ON public.forms
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER jobs_updated_at
  BEFORE UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Requires superuser / Supabase dashboard — fires on new user registration:
-- CREATE TRIGGER on_auth_user_created
--   AFTER INSERT ON auth.users
--   FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.activity_log  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.form_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_photos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites          ENABLE ROW LEVEL SECURITY;

-- activity_log
CREATE POLICY "approved users insert activity" ON public.activity_log
  FOR INSERT WITH CHECK (is_approved());
CREATE POLICY "approved users read activity" ON public.activity_log
  FOR SELECT USING (is_approved());

-- documents
CREATE POLICY "approved users insert documents" ON public.documents
  FOR INSERT WITH CHECK (is_approved());
CREATE POLICY "approved users read documents" ON public.documents
  FOR SELECT USING (is_approved());
CREATE POLICY "owner or admin update documents" ON public.documents
  FOR UPDATE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));
CREATE POLICY "owner or admin delete documents" ON public.documents
  FOR DELETE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));

-- form_templates (open — config data managed in-app by admins)
CREATE POLICY "open_all_form_templates" ON public.form_templates
  FOR ALL USING (true) WITH CHECK (true);

-- forms
CREATE POLICY "approved users insert forms" ON public.forms
  FOR INSERT WITH CHECK (is_approved());
CREATE POLICY "approved users read forms" ON public.forms
  FOR SELECT USING (is_approved());
CREATE POLICY "owner or admin update forms" ON public.forms
  FOR UPDATE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));
CREATE POLICY "owner or admin delete forms" ON public.forms
  FOR DELETE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));

-- jobs
CREATE POLICY "approved users insert jobs" ON public.jobs
  FOR INSERT WITH CHECK (is_approved());
CREATE POLICY "approved users read jobs" ON public.jobs
  FOR SELECT USING (is_approved());
CREATE POLICY "owner or admin update jobs" ON public.jobs
  FOR UPDATE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));
CREATE POLICY "admin delete jobs" ON public.jobs
  FOR DELETE USING (is_admin());

-- profiles
CREATE POLICY "read profiles" ON public.profiles
  FOR SELECT USING ((SELECT auth.uid()) = id OR is_admin());
CREATE POLICY "update own profile or admin" ON public.profiles
  FOR UPDATE USING ((SELECT auth.uid()) = id OR is_admin());

-- site_photos (public — rows accessed via storage public URLs)
CREATE POLICY "anon_all_site_photos" ON public.site_photos
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- sites
CREATE POLICY "approved users insert sites" ON public.sites
  FOR INSERT WITH CHECK (is_approved());
CREATE POLICY "approved users read sites" ON public.sites
  FOR SELECT USING (is_approved());
CREATE POLICY "owner or admin update sites" ON public.sites
  FOR UPDATE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));
CREATE POLICY "owner or admin delete sites" ON public.sites
  FOR DELETE USING (is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid()))));


-- ============================================================
-- STORAGE BUCKETS
-- Create these via Supabase dashboard or management API.
-- SQL shown for reference only (storage schema is managed by Supabase).
-- ============================================================

-- INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
--   ('site-photos',    'site-photos',    true,  10485760, null),
--   ('job-pdfs',       'job-pdfs',       true,  20971520, null),
--   ('form-templates', 'form-templates', true,  20971520, ARRAY['application/pdf']),
--   ('form-exports',   'form-exports',   false, null,     null);

-- Storage RLS policies (apply via Supabase dashboard or MCP):
--   site-photos:    FOR ALL TO public  USING (bucket_id = 'site-photos')
--   job-pdfs:       FOR ALL TO public  USING (bucket_id = 'job-pdfs')
--   form-templates: FOR ALL TO public  USING (bucket_id = 'form-templates')
--   form-exports SELECT: bucket_id='form-exports' AND (SELECT auth.role())='authenticated'
--   form-exports INSERT: bucket_id='form-exports' AND (SELECT auth.role())='authenticated'
