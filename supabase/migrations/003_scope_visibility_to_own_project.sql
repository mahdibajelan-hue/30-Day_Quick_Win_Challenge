-- ============================================================
-- Migration: scope manager visibility to their own project, and
-- within a project, to their own organization's data — except the
-- currently-selected winning Quick Win proposal, which becomes fully
-- visible to every manager on that project once decided.
--
-- Previously (from the original bootstrap migration), any authenticated
-- manager could SELECT every row of check_ins / client_reports /
-- quick_win_decisions / quick_win_progress across ALL projects and
-- organizations — that was fine for early testing but is wrong for real
-- use: a پیمانکار should not see a مشاور's X-Ray report, issues, risks,
-- or Quick Win proposal (or any other project's data at all), only the
-- proposal the admin actually picked as the winner for their own project.
--
-- This drops whatever SELECT policies currently exist on these 4 tables
-- (by name, dynamically, since this repo's original policy names aren't
-- available here) and replaces them with the scoped versions below.
-- INSERT/UPDATE/ALL policies (including the admin "for all" ones and the
-- manager insert-only-their-own-project-and-org ones) are untouched.
-- ============================================================

do $$
declare
    pol record;
begin
    for pol in
        select schemaname, tablename, policyname
        from pg_policies
        where tablename in ('check_ins', 'client_reports', 'quick_win_decisions', 'quick_win_progress')
          and cmd = 'SELECT'
    loop
        execute format('drop policy %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);
    end loop;
end $$;

-- check_ins: admin sees everything; a manager sees their own project+organization's
-- own submissions, plus (once decided) the full row of whichever proposal on their
-- project was selected as the winning Quick Win — regardless of which organization
-- submitted it.
create policy "scoped read on check_ins" on check_ins
    for select using (
        is_admin()
        or exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.project_name = check_ins.project_name
            and app_users.organization = check_ins.organization
        )
        or exists (
            select 1 from quick_win_decisions d
            join app_users au on au.user_id = auth.uid() and au.project_name = d.project_name
            where d.project_name = check_ins.project_name
            and d.selected_organization = check_ins.organization
            and d.selected_title = check_ins.quick_win_title
        )
    );

-- client_reports: project-master-data (contract basics, milestone), not one
-- organization's private opinion — visible to every manager on that project,
-- just not to other projects.
create policy "scoped read on client_reports" on client_reports
    for select using (
        is_admin()
        or exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.project_name = client_reports.project_name
        )
    );

-- quick_win_decisions / quick_win_progress: the decided winner and its execution
-- log are shared project state once they exist — visible to every manager on
-- that project (never other projects).
create policy "scoped read on quick_win_decisions" on quick_win_decisions
    for select using (
        is_admin()
        or exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.project_name = quick_win_decisions.project_name
        )
    );

create policy "scoped read on quick_win_progress" on quick_win_progress
    for select using (
        is_admin()
        or exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.project_name = quick_win_progress.project_name
        )
    );
