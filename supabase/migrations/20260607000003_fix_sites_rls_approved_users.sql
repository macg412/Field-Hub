-- Align sites RLS with the documents/forms pattern:
-- INSERT/SELECT → is_approved(); UPDATE/DELETE → owner or admin.

DROP POLICY IF EXISTS "Authenticated users can create sites"   ON public.sites;
DROP POLICY IF EXISTS "Authenticated users can read all sites" ON public.sites;
DROP POLICY IF EXISTS "Authenticated users can update sites"   ON public.sites;
DROP POLICY IF EXISTS "Authenticated users can delete sites"   ON public.sites;

CREATE POLICY "approved users insert sites" ON public.sites
  FOR INSERT WITH CHECK (is_approved());

CREATE POLICY "approved users read sites" ON public.sites
  FOR SELECT USING (is_approved());

CREATE POLICY "owner or admin update sites" ON public.sites
  FOR UPDATE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );

CREATE POLICY "owner or admin delete sites" ON public.sites
  FOR DELETE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );
