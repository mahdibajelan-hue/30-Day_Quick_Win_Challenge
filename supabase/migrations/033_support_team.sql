-- «تیم پشتیبانی کارفرما» — a third kind of app_users row, alongside
-- manager/admin: someone the admin hands specific tasks off to across
-- EVERY project, without making them a real org member of any one
-- project (no user_project_access row) and without making them a
-- system admin (no user/project management, no evaluate/decide/close).
--
-- Kept as a flag on top of role (still only 'manager'/'admin') rather
-- than a third role value, so every existing `role === 'admin'` check
-- app-wide keeps working unchanged — a support-team member is a
-- 'manager' row with is_support_team = true.

alter table app_users add column if not exists is_support_team boolean not null default false;

comment on column app_users.is_support_team is 'تیم پشتیبانی کارفرما: read access to every project (granted below) and task-assignable, but not a system admin and not a real org member of any project (no user_project_access row).';

-- Mirrors is_admin() exactly (self-row read is always permitted regardless
-- of RLS, so — like is_admin() — this needs no elevated privilege).
create or replace function is_support_team()
returns boolean
language sql
stable
as $$
    select coalesce((select is_support_team from app_users where user_id = auth.uid()), false);
$$;

-- Purely additive SELECT policies, one per project-scoped table a support-
-- team member needs to browse — same pattern already used for "guide
-- project visible to all" (migration 017): Postgres OR's multiple
-- permissive policies for the same command together, so each of these
-- only ever *widens* read access and never touches, replaces or needs to
-- know the exact text of whatever scoped-read policy already exists on
-- that table. Write access is deliberately untouched: a support-team
-- member's only write path stays the existing "responsible person can
-- submit task for approval" policy on case_updates (migration 024),
-- which already keys off app_users.email = responsible_email and was
-- always independent of user_project_access.
create policy "support team can view all projects" on projects
    for select using (is_support_team());

create policy "support team can view all cases" on cases
    for select using (is_support_team());

create policy "support team can view all case_updates" on case_updates
    for select using (is_support_team());

create policy "support team can view all client_reports" on client_reports
    for select using (is_support_team());

create policy "support team can view all check_ins" on check_ins
    for select using (is_support_team());

create policy "support team can view all approval_requests" on approval_requests
    for select using (is_support_team());

-- list_project_users (migration 022) drove every "مسئول/PM" picker from
-- user_project_access — a support-team member has no row there by design,
-- so they could never be picked as a task's مسئول and could never call
-- this function themselves for a project they're not a real member of.
-- Both gaps are fixed here: the caller-permission check gains
-- is_support_team(), and every support-team member is unioned into the
-- result for EVERY project (so they show up in the مسئول dropdown
-- regardless of which project is being asked about), labeled with their
-- own "organization" so they're distinguishable in the picker.
create or replace function list_project_users(p_project_name text)
returns table (
    user_id uuid,
    email text,
    first_name text,
    last_name text,
    organization text
)
language sql
stable
security definer
set search_path = public
as $$
    select au.user_id, au.email, au.first_name, au.last_name, upa.organization
    from user_project_access upa
    join app_users au on au.user_id = upa.user_id
    where upa.project_name = p_project_name
      and (
        is_admin()
        or is_support_team()
        or exists (
            select 1 from user_project_access mine
            where mine.user_id = auth.uid()
              and mine.project_name = p_project_name
        )
      )
    union
    select au.user_id, au.email, au.first_name, au.last_name, 'پشتیبانی کارفرما' as organization
    from app_users au
    where au.is_support_team = true
      and (
        is_admin()
        or is_support_team()
        or exists (
            select 1 from user_project_access mine
            where mine.user_id = auth.uid()
              and mine.project_name = p_project_name
        )
      )
    order by first_name nulls last, last_name nulls last, email;
$$;

grant execute on function list_project_users(text) to authenticated;
