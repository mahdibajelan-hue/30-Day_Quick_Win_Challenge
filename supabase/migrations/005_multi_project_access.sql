-- ============================================================
-- Migration: let one user hold access to several projects, each with
-- its own organization (کارفرما/مشاور/پیمانکار) — e.g. a consultant
-- staffed as مشاور on one project and پیمانکار on another. The system
-- role (مدیر پروژه / ادمین سامانه) stays a single, global attribute of
-- the user — only project+organization access becomes multi-valued.
--
-- app_users.project_name / app_users.organization become deprecated:
-- the app no longer reads or writes them after this migration ships.
-- They are intentionally NOT dropped here (a production schema change
-- I can't verify nothing else depends on) — safe to drop later once
-- you've confirmed everything works from user_project_access instead.
-- ============================================================

create table if not exists user_project_access (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    user_id uuid not null references auth.users(id) on delete cascade,
    project_name text not null,
    organization text not null,
    unique (user_id, project_name, organization)
);

alter table user_project_access enable row level security;

create policy "admin full access on user_project_access" on user_project_access
    for all using (is_admin()) with check (is_admin());

create policy "self read own project access" on user_project_access
    for select using (user_id = auth.uid());

-- Backfill: every existing single project+org assignment becomes that
-- user's first grant.
insert into user_project_access (user_id, project_name, organization)
select user_id, project_name, organization
from app_users
where project_name is not null and organization is not null
on conflict (user_id, project_name, organization) do nothing;

-- Re-point the manager-visibility SELECT policies (added in migration 003)
-- from app_users' single project/org columns to user_project_access, so a
-- manager sees data for EVERY project/org they now hold a grant for.
drop policy if exists "scoped read on check_ins" on check_ins;
create policy "scoped read on check_ins" on check_ins
    for select using (
        is_admin()
        or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = check_ins.project_name
            and upa.organization = check_ins.organization
        )
        or exists (
            select 1 from quick_win_decisions d
            join user_project_access upa on upa.user_id = auth.uid() and upa.project_name = d.project_name
            where d.project_name = check_ins.project_name
            and d.selected_organization = check_ins.organization
            and d.selected_title = check_ins.quick_win_title
        )
    );

drop policy if exists "scoped read on client_reports" on client_reports;
create policy "scoped read on client_reports" on client_reports
    for select using (
        is_admin()
        or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = client_reports.project_name
        )
    );

drop policy if exists "scoped read on quick_win_decisions" on quick_win_decisions;
create policy "scoped read on quick_win_decisions" on quick_win_decisions
    for select using (
        is_admin()
        or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = quick_win_decisions.project_name
        )
    );

drop policy if exists "scoped read on quick_win_progress" on quick_win_progress;
create policy "scoped read on quick_win_progress" on quick_win_progress
    for select using (
        is_admin()
        or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = quick_win_progress.project_name
        )
    );

-- Re-point the manager INSERT policy on client_reports (کارفرما-only,
-- added in migration 002) the same way.
drop policy if exists "client managers can insert own project client_reports" on client_reports;
create policy "client managers can insert own project client_reports" on client_reports
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = client_reports.project_name
            and upa.organization = 'کارفرما'
        )
    );

-- check_ins' manager INSERT policy isn't tracked in any migration in this
-- repo (it predates them), so its exact name is unknown here. Find it
-- dynamically — any non-admin INSERT policy on check_ins — and replace it
-- the same way; this is a no-op if no such policy exists.
do $$
declare
    pol record;
begin
    for pol in
        select policyname from pg_policies
        where tablename = 'check_ins' and cmd = 'INSERT' and policyname not ilike '%admin%'
    loop
        execute format('drop policy %I on check_ins', pol.policyname);
    end loop;
end $$;

create policy "manager insert own project org on check_ins" on check_ins
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
            and upa.project_name = check_ins.project_name
            and upa.organization = check_ins.organization
        )
    );
