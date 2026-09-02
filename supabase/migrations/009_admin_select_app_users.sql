-- ============================================================
-- Migration: let an admin see every row of app_users, not just their own.
--
-- Migration 004 gave admins UPDATE/DELETE on app_users but — per its own
-- comment — assumed a SELECT-all-for-admin policy already existed from
-- before this repo tracked migrations, and never verified that assumption
-- against the real database. It didn't exist: an admin's SELECT on
-- app_users (مدیریت کاربران's user list, and its "افزودن دسترسی پروژه به
-- کاربر" dropdown) has only ever returned the admin's own row, filtered by
-- the row-owner-only SELECT policy that predates this repo. So a user
-- created directly in Supabase Authentication could log in, get their
-- app_users row auto-created (migration 008 fixed the INSERT side of
-- this), and still never show up for the admin to grant access to —
-- because the admin's own query could never see that row in the first
-- place, regardless of whether it existed.
-- ============================================================

create policy "admin select app_users" on app_users
    for select using (is_admin());
