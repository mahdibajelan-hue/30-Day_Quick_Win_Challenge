-- ============================================================
-- Migration: "حذف پروژه" now purges a project's historical report
-- rows too (check_ins, client_reports, quick_win_decisions,
-- quick_win_progress, quick_win_evaluations) instead of only revoking
-- access and removing the projects row — see deleteProject() in
-- index.html. Without this, every aggregate view (Overview, انتخاب
-- Quick Win, پیگیری اجرا, گزارش اجرایی) kept showing a "deleted"
-- project's data forever, since they read these tables directly and
-- never cross-checked the current projects list.
--
-- client_reports and quick_win_evaluations already carry an admin
-- "for all" policy (migration 002_expanded_reports.sql), so admin
-- DELETE already works there. check_ins / quick_win_decisions /
-- quick_win_progress are believed to carry an equivalent admin "for
-- all" policy from the original bootstrap migration that predates
-- this repo's tracked history (003_scope_visibility_to_own_project.sql
-- says as much when it replaces only their SELECT policies), but since
-- that can't be verified from the files in this repo, this adds an
-- explicit, additive admin DELETE policy on those three tables so the
-- purge is guaranteed to work rather than silently deleting zero rows
-- under RLS. Redundant with any pre-existing admin policy is harmless —
-- permissive RLS policies for the same command simply OR together.
-- ============================================================

drop policy if exists "admin delete on check_ins" on check_ins;
create policy "admin delete on check_ins" on check_ins
    for delete using (is_admin());

drop policy if exists "admin delete on quick_win_decisions" on quick_win_decisions;
create policy "admin delete on quick_win_decisions" on quick_win_decisions
    for delete using (is_admin());

drop policy if exists "admin delete on quick_win_progress" on quick_win_progress;
create policy "admin delete on quick_win_progress" on quick_win_progress
    for delete using (is_admin());
