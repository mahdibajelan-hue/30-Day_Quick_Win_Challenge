-- Issue Control Tower: a project-wide issue register, separate from the
-- Quick Win cases/case_updates model. A Quick Win case is "the one proposal
-- a project picked to execute"; an Issue is any problem worth tracking to
-- closure, whether or not it ever becomes a Quick Win — so this is a new
-- pair of tables (issues / issue_updates) rather than a new case_updates
-- kind, mirroring the cases/case_updates shape (migration 024) closely:
-- one row per issue, plus an append-only timeline of lifecycle/comment/
-- action entries against it.
--
-- Deliberately scoped down from a full multi-dimensional taxonomy: one
-- severity scale (بحرانی/زیاد/متوسط/کم) reused as both "severity" and
-- "priority" — this app already made the same call once (Quick Win
-- evaluation's weighted-score removal) and every other severity-style field
-- in this schema (case problem_areas, risk_register) uses this exact same
-- four-level scale. "Responsible unit" is a new, small, EPC-functional
-- vocabulary (Engineering/Procurement/Construction/...) — a genuinely
-- different axis from the existing کارفرما/مشاور/پیمانکار organization
-- model, not a duplicate of it.

-- ============================================================
-- 1. issues — one row per registered issue
-- ============================================================
create table issues (
    id bigint generated always as identity primary key,
    project_name text not null,
    case_id bigint references cases(id) on delete set null,

    title text not null,
    description text,
    responsible_unit text,

    severity text not null default 'متوسط'
        check (severity in ('بحرانی', 'زیاد', 'متوسط', 'کم')),
    status text not null default 'شناسایی‌شده'
        check (status in (
            'شناسایی‌شده', 'تخصیص‌یافته', 'اقدام برنامه‌ریزی‌شده',
            'در حال اجرا', 'حل‌شده', 'تأییدشده', 'بسته‌شده', 'رد‌شده'
        )),

    responsible_name text,
    responsible_email text,
    raised_by text,

    date_raised date not null default current_date,
    target_date date,
    actual_closure_date date,

    root_cause text,
    corrective_action text,
    preventive_action text,
    latest_update text,
    next_action text,

    created_by text,
    created_at timestamptz not null default now()
);

create index issues_project_idx on issues (project_name);
create index issues_project_status_idx on issues (project_name, status);
create index issues_case_id_idx on issues (case_id) where case_id is not null;

-- ============================================================
-- 2. issue_updates — append-only timeline: lifecycle transition, comment,
--    or a corrective/preventive action note (including an "escalated to
--    X" entry, logged as a plain action note rather than a routed
--    notification — this migration adds no escalation-email plumbing).
-- ============================================================
create table issue_updates (
    id bigint generated always as identity primary key,
    issue_id bigint not null references issues(id) on delete cascade,
    kind text not null check (kind in ('lifecycle', 'comment', 'action')),
    stage text,
    comment text,
    created_by text,
    created_at timestamptz not null default now()
);

create index issue_updates_issue_id_idx on issue_updates (issue_id);

-- ============================================================
-- 3. RLS — issues
-- ============================================================
alter table issues enable row level security;

-- An Issue is a project-wide concern from the moment it's raised (unlike a
-- still-open Quick Win proposal) — every org on the project needs to see
-- what's blocking it, not just whoever raised it. Same project-only (no
-- organization filter) scoped-read shape as a decided/executing case.
create policy "scoped read on issues" on issues
    for select using (
        is_admin()
        or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
              and upa.project_name = issues.project_name
        )
    );

create policy "guide project issues visible to all" on issues
    for select using (
        exists (select 1 from projects where projects.name = issues.project_name and projects.is_guide = true)
    );

create policy "admin insert on issues" on issues
    for insert with check (is_admin());

-- Any project member (any org) can raise an issue against their own
-- project — issues are meant to surface cross-org problems, so this is
-- deliberately not org-scoped the way a Quick Win proposal insert is.
create policy "project member insert on issues" on issues
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
              and upa.project_name = issues.project_name
        )
    );

create policy "admin update on issues" on issues
    for update using (is_admin()) with check (is_admin());

-- The person named as an issue's responsible owner can work it to closure
-- without needing an admin in the loop for every status change — mirrors
-- case_updates' "responsible person can submit task for approval" policy,
-- generalized from one field (task_status) to the small set of fields the
-- lock trigger below actually lets this update touch.
create policy "responsible person can update own issue" on issues
    for update
    using (
        exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = issues.responsible_email)
    )
    with check (
        exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = issues.responsible_email)
    );

create policy "admin delete on issues" on issues
    for delete using (is_admin());

-- Same reasoning as case_updates_lock_privileged_fields (migration 024/028):
-- the responsible-person UPDATE policy's using/with check only constrain
-- *who* can match a row, not *which columns* they rewrite — without this
-- trigger the same UPDATE could silently also rewrite severity, ownership,
-- dates, project_name, etc. Non-admins keep exactly the columns needed to
-- work an issue to closure: status, the CAPA/update text fields, and the
-- actual closure date.
create or replace function issues_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.project_name := old.project_name;
        new.case_id := old.case_id;
        new.title := old.title;
        new.description := old.description;
        new.responsible_unit := old.responsible_unit;
        new.severity := old.severity;
        new.responsible_name := old.responsible_name;
        new.responsible_email := old.responsible_email;
        new.raised_by := old.raised_by;
        new.date_raised := old.date_raised;
        new.target_date := old.target_date;
        new.created_by := old.created_by;
        new.created_at := old.created_at;
    end if;
    return new;
end;
$$;

drop trigger if exists issues_lock_privileged_fields on issues;
create trigger issues_lock_privileged_fields
    before update on issues
    for each row
    execute function issues_lock_privileged_fields();

-- ============================================================
-- 4. RLS — issue_updates
-- ============================================================
alter table issue_updates enable row level security;

create policy "admin full access on issue_updates" on issue_updates
    for all using (is_admin()) with check (is_admin());

create policy "scoped read on issue_updates" on issue_updates
    for select using (
        is_admin()
        or exists (
            select 1 from issues i
            join user_project_access upa on upa.user_id = auth.uid() and upa.project_name = i.project_name
            where i.id = issue_updates.issue_id
        )
    );

create policy "guide project issue_updates visible to all" on issue_updates
    for select using (
        exists (
            select 1 from issues i
            join projects p on p.name = i.project_name
            where i.id = issue_updates.issue_id and p.is_guide = true
        )
    );

-- A timeline entry only ever appends a new row (never rewrites the issue
-- itself), so this is safe to open to every project member rather than
-- gating it the way issues' own UPDATE policies are gated.
create policy "project member insert on issue_updates" on issue_updates
    for insert with check (
        exists (
            select 1 from issues i
            join user_project_access upa on upa.user_id = auth.uid() and upa.project_name = i.project_name
            where i.id = issue_updates.issue_id
        )
    );
