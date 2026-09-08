-- Redesign backlog (P1): "ادغام سه جدول اجرا (decisions/progress/tasks) در
-- یک Case". Today a single Quick Win's story is spread across five places:
-- the qw_* columns of check_ins (the proposal), quick_win_evaluations (its
-- score), quick_win_decisions (which one won, one row per project),
-- quick_win_progress (a percent-complete log) and quick_win_tasks (its
-- checklist). This migration introduces two new tables — `cases` (one row
-- per proposal, carrying its own evaluation/decision fields once those
-- happen to it) and `case_updates` (the execution-phase log: a progress
-- entry or a task, discriminated by `kind`) — and backfills them from the
-- five existing sources.
--
-- Deliberately NON-DESTRUCTIVE: nothing below drops, renames or writes to
-- check_ins/quick_win_decisions/quick_win_progress/quick_win_tasks/
-- quick_win_evaluations. They keep working exactly as before until the
-- frontend/edge functions are cut over to the new tables in a later change;
-- until then this is a parallel copy, and if anything about the new model
-- turns out wrong there is nothing to recover — the originals are untouched.

-- ============================================================
-- 1. cases — one row per Quick Win proposal
-- ============================================================
create table cases (
    id bigint generated always as identity primary key,
    project_name text not null,
    organization text not null,
    status text not null default 'پیشنهاد'
        check (status in ('پیشنهاد', 'ارزیابی‌شده', 'انتخاب‌شده', 'در حال اجرا', 'بسته‌شده')),

    proposed_at timestamptz not null default now(),
    user_id uuid,
    created_by text,

    -- Problem/proposal (from check_ins qw_* columns)
    problem_area text,
    problem_area_other text,
    consequences jsonb,
    consequence_other text,
    consequence_description text,
    title text not null,
    action_details text,
    rationale text,
    expected_result text,

    -- Realization plan
    plan_action text,
    plan_responsible text,
    plan_units_involved text,
    plan_start_date date,
    plan_target_date date,
    plan_prerequisite text,
    plan_decision_needed text,
    plan_deliverable text,

    -- KPI + estimated impact
    kpi_name text,
    kpi_current text,
    kpi_target_30d text,
    impact_delay_days numeric,
    impact_progress_increase numeric,
    impact_cost_avoided numeric,
    impact_issues_closed numeric,
    impact_docs_resolved numeric,
    impact_fronts_freed text,
    impact_other text,

    -- Support ask
    support_types jsonb,
    support_other_text text,
    support_needed text,
    counter_commitment text,
    time_estimate text,
    final_reflection text,

    -- Evaluation (from quick_win_evaluations)
    score_time numeric,
    score_cost numeric,
    score_urgency numeric,
    score_feasibility numeric,
    score_leverage numeric,
    weighted_score numeric,
    decision text,
    evaluated_by text,
    evaluated_at timestamptz,

    -- Decision (from quick_win_decisions — only set once this case is THE
    -- selected one for its project)
    decided_by text,
    decided_at timestamptz,
    execution_target_date date,

    -- Result/value at close (redesign report, section A: the gap where the
    -- system captures estimated impact at proposal time but never captures
    -- what actually happened)
    actual_result text,
    actual_value_json jsonb,
    closed_at timestamptz,

    created_at timestamptz not null default now()
);

create index cases_project_org_idx on cases (project_name, organization);
create index cases_project_status_idx on cases (project_name, status);

-- ============================================================
-- 2. case_updates — execution-phase log: a progress entry or a task
-- ============================================================
create table case_updates (
    id bigint generated always as identity primary key,
    case_id bigint not null references cases(id) on delete cascade,
    kind text not null check (kind in ('progress', 'task')),
    created_at timestamptz not null default now(),
    created_by text,

    -- kind = 'progress'
    status text,
    progress_percent numeric,
    note text,
    reported_by text,

    -- kind = 'task'
    title text,
    responsible_name text,
    responsible_email text,
    due_date date,
    task_status text
        check (task_status in ('باز', 'در حال انجام', 'در انتظار تایید', 'انجام‌شده')),
    completed_at timestamptz,
    overdue_notified_at timestamptz,
    submitted_at timestamptz,
    submitted_note text
);

create index case_updates_case_id_idx on case_updates (case_id);
create index case_updates_overdue_idx on case_updates (due_date, task_status, overdue_notified_at) where kind = 'task';

-- ============================================================
-- 3. RLS — cases
-- ============================================================
alter table cases enable row level security;

-- A still-open proposal (not yet decided) is only visible to the org that
-- submitted it, mirroring check_ins' own org-scoped read today. Once it has
-- been decided/is executing/closed, it becomes a project-wide concern and
-- opens up to every org on the project — mirroring quick_win_decisions'
-- project-only (no organization filter) scoped-read today, which is why an
-- already-decided Quick Win is visible to every manager on the project
-- regardless of which org proposed it.
create policy "scoped read on cases" on cases
    for select using (
        is_admin()
        or (
            status in ('پیشنهاد', 'ارزیابی‌شده')
            and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid()
                  and upa.project_name = cases.project_name
                  and upa.organization = cases.organization
            )
        )
        or (
            status in ('انتخاب‌شده', 'در حال اجرا', 'بسته‌شده')
            and exists (
                select 1 from user_project_access upa
                where upa.user_id = auth.uid()
                  and upa.project_name = cases.project_name
            )
        )
    );

create policy "guide project cases visible to all" on cases
    for select using (
        exists (select 1 from projects where projects.name = cases.project_name and projects.is_guide = true)
    );

create policy "admin insert on cases" on cases
    for insert with check (is_admin());

-- A manager proposes a new Quick Win for their own project/org, same as
-- inserting a qw_* check_ins row today — always starts at 'پیشنهاد', never
-- pre-decided.
create policy "manager insert own project org on cases" on cases
    for insert with check (
        status = 'پیشنهاد'
        and exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid()
              and upa.project_name = cases.project_name
              and upa.organization = cases.organization
        )
    );

-- Evaluating/deciding/closing a case is admin-only today (selectionView's
-- evaluate/decide controls and trackingView's close are both isAdmin-gated);
-- a proposing manager can submit a new case but never edit one after
-- submission, matching check_ins' qw_* rows being insert-only today.
create policy "admin update on cases" on cases
    for update using (is_admin()) with check (is_admin());

create policy "admin delete on cases" on cases
    for delete using (is_admin());

-- ============================================================
-- 4. RLS — case_updates
-- ============================================================
alter table case_updates enable row level security;

create policy "admin full access on case_updates" on case_updates
    for all using (is_admin()) with check (is_admin());

create policy "scoped read on case_updates" on case_updates
    for select using (
        is_admin()
        or exists (
            select 1 from cases c
            join user_project_access upa on upa.user_id = auth.uid() and upa.project_name = c.project_name
            where c.id = case_updates.case_id
        )
    );

create policy "guide project case_updates visible to all" on case_updates
    for select using (
        exists (
            select 1 from cases c
            join projects p on p.name = c.project_name
            where c.id = case_updates.case_id and p.is_guide = true
        )
    );

-- Mirrors quick_win_tasks' own "responsible person can submit task for
-- approval" policy (migration 018) exactly, scoped to kind = 'task' rows.
create policy "responsible person can submit task for approval" on case_updates
    for update
    using (
        kind = 'task'
        and task_status <> 'انجام‌شده'
        and exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = case_updates.responsible_email)
    )
    with check (
        kind = 'task'
        and task_status = 'در انتظار تایید'
        and exists (select 1 from app_users where app_users.user_id = auth.uid() and app_users.email = case_updates.responsible_email)
    );

-- Same reasoning as quick_win_tasks_lock_privileged_fields (migration 020):
-- the submit-for-approval policy's using/with check only constrain
-- task_status on the row it matches — without this trigger, the same UPDATE
-- could silently rewrite title/due_date/responsible_email/etc. in the same
-- call. submitted_at/submitted_note are deliberately NOT reset since the
-- legitimate submit action needs to set them.
create or replace function case_updates_lock_privileged_fields()
returns trigger
language plpgsql
as $$
begin
    if not is_admin() then
        new.case_id := old.case_id;
        new.kind := old.kind;
        new.created_by := old.created_by;
        new.created_at := old.created_at;
        new.status := old.status;
        new.progress_percent := old.progress_percent;
        new.note := old.note;
        new.reported_by := old.reported_by;
        new.title := old.title;
        new.responsible_name := old.responsible_name;
        new.responsible_email := old.responsible_email;
        new.due_date := old.due_date;
        new.completed_at := old.completed_at;
        new.overdue_notified_at := old.overdue_notified_at;
    end if;
    return new;
end;
$$;

drop trigger if exists case_updates_lock_privileged_fields on case_updates;
create trigger case_updates_lock_privileged_fields
    before update on case_updates
    for each row
    execute function case_updates_lock_privileged_fields();

-- ============================================================
-- 5. Backfill from the five existing tables (copy, not move)
-- ============================================================

-- One case per qw_* check_ins row.
insert into cases (
    project_name, organization, status, proposed_at, user_id,
    problem_area, problem_area_other, consequences, consequence_other, consequence_description,
    title, action_details, rationale, expected_result,
    plan_action, plan_responsible, plan_units_involved, plan_start_date, plan_target_date,
    plan_prerequisite, plan_decision_needed, plan_deliverable,
    kpi_name, kpi_current, kpi_target_30d,
    impact_delay_days, impact_progress_increase, impact_cost_avoided, impact_issues_closed,
    impact_docs_resolved, impact_fronts_freed, impact_other,
    support_types, support_other_text, support_needed, counter_commitment, time_estimate, final_reflection,
    created_at
)
select
    ci.project_name, ci.organization, 'پیشنهاد', ci.created_at, ci.user_id,
    ci.qw_bottleneck_area, ci.qw_bottleneck_area_other, ci.qw_consequences, ci.qw_consequence_other, ci.qw_consequence_description,
    ci.quick_win_title, ci.action_details, ci.qw_rationale, ci.tangible_result,
    ci.plan_main_action, ci.plan_responsible, ci.plan_units_involved, ci.plan_start_date, ci.plan_target_date,
    ci.plan_prerequisite, ci.plan_decision_needed, ci.plan_deliverable,
    ci.kpi_name, ci.kpi_current, ci.kpi_target_30d,
    ci.impact_delay_days, ci.impact_progress_increase, ci.impact_cost_avoided, ci.impact_issues_closed,
    ci.impact_docs_resolved, ci.impact_fronts_freed, ci.impact_other,
    ci.support_types, ci.support_other_text, ci.support_needed, ci.counter_commitment, ci.time_estimate, ci.final_reflection,
    ci.created_at
from check_ins ci
where ci.quick_win_title is not null;

-- Layer evaluation scores onto the matching case (same project+org+proposal
-- timestamp — the same key quick_win_evaluations itself uses).
update cases c
set score_time = e.score_time,
    score_cost = e.score_cost,
    score_urgency = e.score_urgency,
    score_feasibility = e.score_feasibility,
    score_leverage = e.score_leverage,
    weighted_score = e.weighted_score,
    decision = e.decision,
    evaluated_by = e.evaluated_by,
    evaluated_at = e.created_at,
    status = case when e.decision = 'Quick Win منتخب' then 'انتخاب‌شده' else 'ارزیابی‌شده' end
from quick_win_evaluations e
where c.project_name = e.project_name
  and c.organization = e.organization
  and c.proposed_at = e.proposal_created_at;

-- Map each project's decision to the one case it points to (latest matching
-- proposal, in the rare case of a duplicate title), for reuse below. A plain
-- session-scoped temp table (not "on commit drop") so this still works
-- whether or not the tool applying this file wraps it in one transaction —
-- it's dropped explicitly at the end of this script instead.
create temporary table _decision_case_map as
select d.project_name, m.case_id
from quick_win_decisions d
join lateral (
    select c2.id as case_id
    from cases c2
    where c2.project_name = d.project_name
      and c2.organization = d.selected_organization
      and c2.title = d.selected_title
    order by c2.proposed_at desc
    limit 1
) m on true;

-- Decided cases: closed if fully complete per the latest progress log,
-- otherwise in execution.
with latest_progress as (
    select distinct on (project_name) project_name, progress_percent, created_at
    from quick_win_progress
    order by project_name, created_at desc
)
update cases c
set decided_by = d.decided_by,
    decided_at = d.created_at,
    execution_target_date = d.target_date,
    status = case when coalesce(lp.progress_percent, 0) >= 100 then 'بسته‌شده' else 'در حال اجرا' end,
    closed_at = case when coalesce(lp.progress_percent, 0) >= 100 then lp.created_at else null end
from quick_win_decisions d
join _decision_case_map m on m.project_name = d.project_name
left join latest_progress lp on lp.project_name = d.project_name
where c.id = m.case_id;

-- Progress log entries, re-parented onto the matched case.
insert into case_updates (case_id, kind, created_at, created_by, status, progress_percent, note, reported_by)
select m.case_id, 'progress', p.created_at, p.reported_by, p.status, p.progress_percent, p.note, p.reported_by
from quick_win_progress p
join _decision_case_map m on m.project_name = p.project_name;

-- Tasks, re-parented onto the matched case.
insert into case_updates (
    case_id, kind, created_at, created_by, title, responsible_name, responsible_email,
    due_date, task_status, completed_at, overdue_notified_at, submitted_at, submitted_note
)
select
    m.case_id, 'task', t.created_at, t.created_by, t.title, t.responsible_name, t.responsible_email,
    t.due_date, t.status, t.completed_at, t.overdue_notified_at, t.submitted_at, t.submitted_note
from quick_win_tasks t
join _decision_case_map m on m.project_name = t.project_name;

-- Best-effort by design: a decision/progress/task row that doesn't match any
-- case (e.g. selected_title drifted from the original proposal's title) is
-- silently skipped here rather than failing the migration — nothing is lost
-- since the source tables are untouched. This notice is the way to catch
-- that at apply-time instead of discovering it later.
do $$
declare
    total_decisions int;
    matched_decisions int;
    total_progress int;
    matched_progress int;
    total_tasks int;
    matched_tasks int;
begin
    select count(*) into total_decisions from quick_win_decisions;
    select count(*) into matched_decisions from _decision_case_map;
    select count(*) into total_progress from quick_win_progress;
    select count(*) into matched_progress from quick_win_progress p join _decision_case_map m on m.project_name = p.project_name;
    select count(*) into total_tasks from quick_win_tasks;
    select count(*) into matched_tasks from quick_win_tasks t join _decision_case_map m on m.project_name = t.project_name;
    raise notice 'cases backfill: % / % quick_win_decisions matched to a case', matched_decisions, total_decisions;
    raise notice 'cases backfill: % / % quick_win_progress rows migrated to case_updates', matched_progress, total_progress;
    raise notice 'cases backfill: % / % quick_win_tasks rows migrated to case_updates', matched_tasks, total_tasks;
end $$;

drop table _decision_case_map;
