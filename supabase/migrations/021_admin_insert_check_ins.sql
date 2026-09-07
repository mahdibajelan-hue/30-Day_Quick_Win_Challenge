-- ============================================================
-- Fix: an admin submitting «اطلاعات تکمیلی» on behalf of a project/
-- organization (via the ci_adminPicker flow in index.html) gets "new
-- row violates row-level security policy for table check_ins".
--
-- check_ins has never actually had an admin-wide INSERT policy. The
-- only INSERT policy is "manager insert own project org on check_ins"
-- (migration 005), which requires the CALLER to hold a
-- user_project_access grant for that exact project+organization — an
-- admin submitting on another project's behalf generally doesn't have
-- one (the whole point of the admin picker is to act on a project the
-- admin isn't personally staffed on). Migration 013's own comment
-- already flagged this as unverified ("check_ins ... believed to carry
-- an equivalent admin 'for all' policy from the original bootstrap
-- migration ... but since that can't be verified from the files in
-- this repo") — this confirms that assumption was wrong. check_ins
-- already has an admin DELETE policy from that same migration; this
-- adds the missing admin INSERT counterpart the same way.
--
-- Purely additive (Postgres OR's multiple permissive policies for the
-- same command together) — the existing manager policy is untouched.
-- ============================================================

drop policy if exists "admin insert on check_ins" on check_ins;
create policy "admin insert on check_ins" on check_ins
    for insert with check (is_admin());
