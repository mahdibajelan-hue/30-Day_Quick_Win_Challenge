-- ============================================================
-- Migration: makes «پروژه راهنما» (the guide/demo project, see migration
-- 014) actually visible to every authenticated user, not just admins.
--
-- The is_guide flag alone never controlled row-level visibility — the
-- existing RLS policies (from the original bootstrap migration and
-- 003_scope_visibility_to_own_project.sql) scope a manager's reads to
-- projects they have an explicit app_users/user_project_access grant
-- for. A regular manager has no such grant for the guide project, so
-- RLS silently hid all of it from them — only admins (who bypass RLS
-- via is_admin()) could ever see it. This was never noticed until a
-- non-admin account actually tested it.
--
-- Fix: add one purely additive SELECT policy per table, scoped only to
-- rows belonging to the guide project. Postgres OR's multiple permissive
-- policies for the same command together, so this only ever *widens*
-- visibility — it can't weaken or replace whatever policies already
-- exist, whether or not this migration knows their exact definition.
-- Guide-project data stays read-only for non-admins (write access is
-- unchanged, still admin-only) since it's meant purely as an example to
-- learn from, matching the earlier request to keep it visible
-- everywhere except نمای کلی (Overview) — see getGuideProjectNames() /
-- loadOverview() / loadTrackingData() in index.html, which are
-- unaffected by this migration.
-- ============================================================

drop policy if exists "guide project visible to all" on projects;
create policy "guide project visible to all" on projects
    for select using (is_guide = true);

drop policy if exists "guide project check_ins visible to all" on check_ins;
create policy "guide project check_ins visible to all" on check_ins
    for select using (
        exists (select 1 from projects where projects.name = check_ins.project_name and projects.is_guide = true)
    );

drop policy if exists "guide project client_reports visible to all" on client_reports;
create policy "guide project client_reports visible to all" on client_reports
    for select using (
        exists (select 1 from projects where projects.name = client_reports.project_name and projects.is_guide = true)
    );

drop policy if exists "guide project quick_win_decisions visible to all" on quick_win_decisions;
create policy "guide project quick_win_decisions visible to all" on quick_win_decisions
    for select using (
        exists (select 1 from projects where projects.name = quick_win_decisions.project_name and projects.is_guide = true)
    );

drop policy if exists "guide project quick_win_progress visible to all" on quick_win_progress;
create policy "guide project quick_win_progress visible to all" on quick_win_progress
    for select using (
        exists (select 1 from projects where projects.name = quick_win_progress.project_name and projects.is_guide = true)
    );

drop policy if exists "guide project quick_win_evaluations visible to all" on quick_win_evaluations;
create policy "guide project quick_win_evaluations visible to all" on quick_win_evaluations
    for select using (
        exists (select 1 from projects where projects.name = quick_win_evaluations.project_name and projects.is_guide = true)
    );

drop policy if exists "guide project quick_win_tasks visible to all" on quick_win_tasks;
create policy "guide project quick_win_tasks visible to all" on quick_win_tasks
    for select using (
        exists (select 1 from projects where projects.name = quick_win_tasks.project_name and projects.is_guide = true)
    );
