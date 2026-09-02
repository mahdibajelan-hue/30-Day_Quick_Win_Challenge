-- ============================================================
-- Migration: allow a freshly-authenticated user (created directly in
-- Supabase Authentication, with no app_users row yet) to create their
-- own minimal profile on first login.
--
-- index.html's resolveProfile() has always tried this self-insert —
-- insert into app_users (user_id, email, role: 'manager') — the
-- moment it finds no existing row for the logged-in user. This is how
-- a user the admin created directly in Supabase Auth (no invite row
-- at all) becomes visible in مدیریت کاربران so the admin can grant
-- them project access.
--
-- But no INSERT policy on app_users has ever permitted this: the
-- table's original, untracked bootstrap policies only ever covered
-- SELECT (own row) and admin-wide access; migration 004 layered
-- UPDATE/DELETE for admins on top of that, but never INSERT for a
-- regular authenticated user. Every such self-insert has therefore
-- been silently rejected by RLS ("new row violates row-level security
-- policy") — the insert resolves with a non-null error and no data,
-- resolveProfile() returns early, currentProfile stays null, and the
-- user is stuck on "دسترسی تعریف‌نشده" forever, with no row ever
-- appearing in app_users for the admin to grant access to.
--
-- role is hard-coded to 'manager' in the WITH CHECK — not just trusted
-- from the client's insert payload — because this insert runs under
-- the publishable/anon key: without that constraint, any authenticated
-- user could insert their own row with role='admin' directly through
-- the Supabase client and grant themselves full admin access.
-- ============================================================

create policy "users can create their own profile" on app_users
    for insert
    to authenticated
    with check (auth.uid() = user_id and role = 'manager');
