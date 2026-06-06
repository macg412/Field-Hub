-- Align forms RLS with the documents pattern:
-- INSERT/SELECT → is_approved(); UPDATE/DELETE → owner or admin.

DROP POLICY IF EXISTS "Authenticated users can create forms"   ON public.forms;
DROP POLICY IF EXISTS "Authenticated users can read all forms" ON public.forms;
DROP POLICY IF EXISTS "Authenticated users can update forms"   ON public.forms;
DROP POLICY IF EXISTS "Authenticated users can delete forms"   ON public.forms;

CREATE POLICY "approved users insert forms" ON public.forms
  FOR INSERT WITH CHECK (is_approved());

CREATE POLICY "approved users read forms" ON public.forms
  FOR SELECT USING (is_approved());

CREATE POLICY "owner or admin update forms" ON public.forms
  FOR UPDATE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );

CREATE POLICY "owner or admin delete forms" ON public.forms
  FOR DELETE USING (
    is_admin() OR (is_approved() AND (created_by = (SELECT auth.uid())))
  );
