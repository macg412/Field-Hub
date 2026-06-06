-- Consolidate duplicate RLS policies to one per table+command.
-- Legacy "Authenticated users" / "anon" policies are OR'd with
-- the newer "approved users" / "owner or admin" policies, making
-- the stricter ones ineffective. Drop the shadowing broad ones.

-- activity_log: drop open anon policies; approved-users ones remain
DROP POLICY IF EXISTS "anon insert activity" ON public.activity_log;
DROP POLICY IF EXISTS "anon read activity"   ON public.activity_log;

-- jobs INSERT: drop uid=created_by check; approved users policy remains
DROP POLICY IF EXISTS "Authenticated users can create jobs" ON public.jobs;

-- jobs SELECT: drop role=authenticated; approved users read policy remains
DROP POLICY IF EXISTS "Authenticated users can read all jobs" ON public.jobs;

-- jobs UPDATE: drop role=authenticated; owner-or-admin policy remains
DROP POLICY IF EXISTS "Authenticated users can update jobs" ON public.jobs;

-- profiles UPDATE: merge uid=id and is_admin() into one policy
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "admin update profiles"              ON public.profiles;
CREATE POLICY "update own profile or admin" ON public.profiles
  FOR UPDATE USING (
    (SELECT auth.uid()) = id OR is_admin()
  );

-- site_photos ALL: drop identical duplicate
DROP POLICY IF EXISTS "auth_all_site_photos" ON public.site_photos;
