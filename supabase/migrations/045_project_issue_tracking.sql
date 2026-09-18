-- ============================================================
-- «پیگیری موانع پروژه‌ها» — a lightweight obstacle/issue tracker, a new
-- tab alongside «پایش اقدامات» (case_updates kind='task'). Deliberately
-- its own table rather than reusing case_updates: an obstacle isn't
-- necessarily tied to a quick-win case_id, and unlike tasks (admin-only
-- creation — see loadTasksView's tasksNewBtn gating) any project member
-- should be able to report one they've hit. The app's JS then reads
-- BOTH tables together for the calendar/KPIs/reports (a lens over two
-- sources, same "don't duplicate data" precedent as the task tower's
-- own comment about not being a second task system).
--
-- Schema, RLS shape and the privileged-fields lock trigger mirror
-- case_updates' own task columns/policies (migrations 024, 020)
-- closely on purpose: same status vocabulary ('باز' -> 'در حال انجام'
-- -> 'در انتظار تایید' -> 'انجام‌شده'), same responsible_name/
-- responsible_email pair (denormalized, matched against app_users.email
-- for RLS — this app never stores a bare auth.uid() FK on these rows),
-- same submit-for-approval flow restricted to the responsible person.
-- ============================================================

create table project_issues (
    id bigint generated always as identity primary key,
    project_name text not null,
    title text not null,
    description text,
    responsible_name text not null,
    responsible_email text not null,
    severity text not null default 'متوسط' check (severity in ('کم', 'متوسط', 'زیاد', 'بحرانی')),
    status text not null default 'باز' check (status in ('باز', 'در حال انجام', 'در انتظار تایید', 'انجام‌شده')),
    due_date date not null,
    created_by text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    submitted_at timestamptz,
    submitted_note text,
    completed_at timestamptz
);

create index project_issues_project_idx on project_issues (project_name);
create index project_issues_due_date_idx on project_issues (due_date);

alter table project_issues enable row level security;

create policy "admin full access on project_issues" on project_issues
    for all using (is_admin()) with check (is_admin());

create policy "scoped read on project_issues" on project_issues
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_issues.project_name
        )
    );

create policy "guide project issues visible to all" on project_issues
    for select using (
        exists (select 1 from projects p where p.name = project_issues.project_name and p.is_guide = true)
    );

-- Any project member (not just admin, unlike task creation) can report
-- an obstacle they've hit on a project they have access to.
create policy "project member can report issue" on project_issues
    for insert with check (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = project_issues.project_name
        )
    );

-- Mirrors case_updates' "responsible person can submit task for
-- approval" (migration 024) exactly, one status forward at a time.
create policy "responsible person can submit issue for approval" on project_issues
    for update
    using (
        status <> 'انجام‌شده'
        and exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = project_issues.responsible_email)
    )
    with check (
        status = 'در انتظار تایید'
        and exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = project_issues.responsible_email)
    );

-- Same reasoning as case_updates_lock_privileged_fields (migration
-- 024): the submit-for-approval policy's using/with check only
-- constrain `status` on the row it matches — without this trigger, the
-- same UPDATE could silently rewrite title/due_date/responsible_email/
-- etc. in the same call. submitted_at/submitted_note are deliberately
-- NOT reset since the legitimate submit action needs to set them.
create or replace function project_issues_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.project_name := old.project_name;
        new.title := old.title;
        new.description := old.description;
        new.responsible_name := old.responsible_name;
        new.responsible_email := old.responsible_email;
        new.severity := old.severity;
        new.due_date := old.due_date;
        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.completed_at := old.completed_at;
    end if;
    return new;
end;
$$;

drop trigger if exists project_issues_lock_privileged_fields on project_issues;
create trigger project_issues_lock_privileged_fields
    before update on project_issues
    for each row
    execute function project_issues_lock_privileged_fields();
