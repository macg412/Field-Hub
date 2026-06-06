-- Fix per-row re-evaluation of auth.uid() / auth.role() in RLS
-- Wrapping auth.uid()/auth.role() in a subquery tells the planner
-- to evaluate them once per statement rather than once per row.
-- Helper functions are also changed from VOLATILE → STABLE so
-- PostgreSQL can cache their result across rows in a single query.

-- 1. Helper functions: VOLATILE → STABLE + subquery-wrapped auth.uid()

CREATE OR REPLACE FUNCTION public.is_approved()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (SELECT auth.uid())
      AND approved = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (SELECT auth.uid())
      AND is_admin = true
      AND approved = true
  );
$$;


-- 2. documents policies

DROP POLICY IF EXISTS "owner or admin delete documents" ON public.documents;
CREATE POLICY "owner or admin delete documents" ON public.documents
  FOR DELETE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );

DROP POLICY IF EXISTS "owner or admin update documents" ON public.documents;
CREATE POLICY "owner or admin update documents" ON public.documents
  FOR UPDATE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );


-- 3. forms policies

DROP POLICY IF EXISTS "Authenticated users can create forms" ON public.forms;
CREATE POLICY "Authenticated users can create forms" ON public.forms
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) = created_by
  );

DROP POLICY IF EXISTS "Authenticated users can delete forms" ON public.forms;
CREATE POLICY "Authenticated users can delete forms" ON public.forms
  FOR DELETE USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can read all forms" ON public.forms;
CREATE POLICY "Authenticated users can read all forms" ON public.forms
  FOR SELECT USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can update forms" ON public.forms;
CREATE POLICY "Authenticated users can update forms" ON public.forms
  FOR UPDATE USING (
    (SELECT auth.role()) = 'authenticated'
  );


-- 4. jobs policies

DROP POLICY IF EXISTS "Authenticated users can create jobs" ON public.jobs;
CREATE POLICY "Authenticated users can create jobs" ON public.jobs
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) = created_by
  );

DROP POLICY IF EXISTS "Authenticated users can read all jobs" ON public.jobs;
CREATE POLICY "Authenticated users can read all jobs" ON public.jobs
  FOR SELECT USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can update jobs" ON public.jobs;
CREATE POLICY "Authenticated users can update jobs" ON public.jobs
  FOR UPDATE USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "owner or admin update jobs" ON public.jobs;
CREATE POLICY "owner or admin update jobs" ON public.jobs
  FOR UPDATE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );


-- 5. profiles policies

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile" ON public.profiles
  FOR UPDATE USING (
    (SELECT auth.uid()) = id
  );

DROP POLICY IF EXISTS "read profiles" ON public.profiles;
CREATE POLICY "read profiles" ON public.profiles
  FOR SELECT USING (
    ((SELECT auth.uid()) = id) OR is_admin()
  );


-- 6. sites policies

DROP POLICY IF EXISTS "Authenticated users can create sites" ON public.sites;
CREATE POLICY "Authenticated users can create sites" ON public.sites
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) = created_by
  );

DROP POLICY IF EXISTS "Authenticated users can delete sites" ON public.sites;
CREATE POLICY "Authenticated users can delete sites" ON public.sites
  FOR DELETE USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can read all sites" ON public.sites;
CREATE POLICY "Authenticated users can read all sites" ON public.sites
  FOR SELECT USING (
    (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can update sites" ON public.sites;
CREATE POLICY "Authenticated users can update sites" ON public.sites
  FOR UPDATE USING (
    (SELECT auth.role()) = 'authenticated'
  );


-- 7. storage.objects policies

DROP POLICY IF EXISTS "Authenticated users can read exports" ON storage.objects;
CREATE POLICY "Authenticated users can read exports" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'form-exports' AND (SELECT auth.role()) = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can upload exports" ON storage.objects;
CREATE POLICY "Authenticated users can upload exports" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'form-exports' AND (SELECT auth.role()) = 'authenticated'
  );
