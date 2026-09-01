-- ============================================================
-- Migration: allow admins to manage users from the مدیریت کاربران
-- panel — change a user's role, reassign their project/organization,
-- delete their access entirely, and edit/cancel a pending invite.
--
-- The bootstrap schema likely already grants admins full access to
-- every table (see migration 003's comment: "the admin 'for all'
-- ones" already existed on check_ins/client_reports/quick_win_* before
-- it ran), which would make this a no-op — but that policy isn't
-- tracked in this repo's migrations, so it can't be confirmed here.
-- This migration only ADDS new, uniquely-named, admin-scoped permissive
-- policies for UPDATE/DELETE — it never touches or drops any existing
-- policy, so it is safe to run whether or not admins already have this
-- access. This matters especially for pending_invites, which already
-- has a (differently-scoped) UPDATE policy that lets a newly-invited
-- user consume their own invite row on first login; Postgres RLS OR's
-- together multiple permissive policies for the same command, so adding
-- an admin policy alongside it is additive and safe either way.
-- ============================================================

create policy "admin update app_users" on app_users
    for update using (is_admin()) with check (is_admin());

create policy "admin delete app_users" on app_users
    for delete using (is_admin());

create policy "admin update pending_invites" on pending_invites
    for update using (is_admin()) with check (is_admin());

create policy "admin delete pending_invites" on pending_invites
    for delete using (is_admin());
