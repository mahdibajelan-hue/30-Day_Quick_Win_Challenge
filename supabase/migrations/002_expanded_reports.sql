-- ============================================================
-- Migration: expanded periodic report content
--   1) client_reports  — new table: کارفرما-only "Form 1"
--      (basic contract info + progress/schedule + next milestone)
--   2) check_ins       — many new columns: 7-area X-Ray, 10 work
--      fronts, top-3 issues/risks, strategic questions, and the
--      expanded Quick Win proposal (problem id, action plan,
--      impact measurement, support needed)
--   3) quick_win_evaluations — new table: PMO-only weighted
--      scoring rubric per proposal (not just the selected winner)
--
-- Run this in the Supabase SQL Editor for the project index.html
-- points to (Project Settings -> Database -> SQL Editor). This is
-- additive except for dropping the 4 old flat status_* columns on
-- check_ins (superseded by area_status/work_fronts below) — safe
-- only because all existing check_ins data is test data.
--
-- Assumes the is_admin() helper function and the app_users table
-- from the original bootstrap migration already exist.
-- ============================================================

-- 1. Client-only periodic "Form 1"
create table if not exists client_reports (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    user_id uuid not null references auth.users(id),
    project_name text not null,

    plan_name text,
    contract_number text,
    contract_type text,
    contract_type_other text,
    contractor_name text,
    consultant_name text,
    client_pm_name text,
    contractor_pm_name text,
    consultant_pm_name text,
    contract_initial_amount numeric,
    contract_current_amount numeric,
    contract_start_date date,
    contract_end_date date,
    contract_duration_months numeric,
    elapsed_months numeric,

    progress_planned numeric,
    progress_physical numeric,
    progress_engineering numeric,
    progress_procurement numeric,
    progress_construction numeric,

    milestone_name text,
    milestone_planned_date date,
    milestone_status text,
    milestone_delay_days numeric
);

alter table client_reports enable row level security;

drop policy if exists "admin full access on client_reports" on client_reports;
create policy "admin full access on client_reports" on client_reports
    for all using (is_admin()) with check (is_admin());

drop policy if exists "client managers can insert own project client_reports" on client_reports;
create policy "client managers can insert own project client_reports" on client_reports
    for insert with check (
        exists (
            select 1 from app_users
            where app_users.user_id = auth.uid()
            and app_users.project_name = client_reports.project_name
            and app_users.organization = 'کارفرما'
        )
    );

drop policy if exists "authenticated app users can read client_reports" on client_reports;
create policy "authenticated app users can read client_reports" on client_reports
    for select using (
        exists (select 1 from app_users where app_users.user_id = auth.uid())
    );


-- 2. Expand check_ins with the richer X-Ray + Quick Win fields
alter table check_ins
    add column if not exists area_status jsonb,
    add column if not exists work_fronts jsonb,
    add column if not exists issues jsonb,
    add column if not exists risks jsonb,
    add column if not exists q_negative_event text,
    add column if not exists bottleneck_root_cause text,
    add column if not exists bottleneck_unlock_action text,
    add column if not exists senior_decision_needed text,
    add column if not exists senior_decision_priority text,
    add column if not exists one_thing_to_change text,
    add column if not exists respondent_position text,
    add column if not exists respondent_contact text,
    add column if not exists qw_form_date date,
    add column if not exists qw_bottleneck_area text,
    add column if not exists qw_bottleneck_area_other text,
    add column if not exists qw_consequences jsonb,
    add column if not exists qw_consequence_other text,
    add column if not exists qw_consequence_description text,
    add column if not exists qw_rationale text,
    add column if not exists plan_main_action text,
    add column if not exists plan_responsible text,
    add column if not exists plan_units_involved text,
    add column if not exists plan_start_date date,
    add column if not exists plan_target_date date,
    add column if not exists plan_prerequisite text,
    add column if not exists plan_decision_needed text,
    add column if not exists plan_deliverable text,
    add column if not exists kpi_name text,
    add column if not exists kpi_current text,
    add column if not exists kpi_target_30d text,
    add column if not exists impact_delay_days numeric,
    add column if not exists impact_progress_increase numeric,
    add column if not exists impact_cost_avoided numeric,
    add column if not exists impact_issues_closed numeric,
    add column if not exists impact_docs_resolved numeric,
    add column if not exists impact_fronts_freed text,
    add column if not exists impact_other text,
    add column if not exists support_types jsonb,
    add column if not exists support_other_text text,
    add column if not exists time_estimate text,
    add column if not exists final_reflection text;

comment on column check_ins.area_status is 'jsonb: {engineering:{status,issue}, procurement:{...}, construction:{...}, contract:{...}, finance:{...}, hse:{...}, quality:{...}}';
comment on column check_ins.work_fronts is 'jsonb: {row:{status,bottleneck}, pipe_supply:{...}, valve_equipment:{...}, welding:{...}, ndt:{...}, coating:{...}, lowering:{...}, backfilling:{...}, crossings:{...}, station_facility:{...}}';
comment on column check_ins.issues is 'jsonb array (<=3): [{description, impact:[tags], severity}]';
comment on column check_ins.risks is 'jsonb array (<=3): [{risk, probability, impact, level, current_action}]';
comment on column check_ins.qw_consequences is 'jsonb array of selected consequence tags';
comment on column check_ins.support_types is 'jsonb array of selected support-type tags';

-- Superseded by area_status (7-area X-Ray) + work_fronts (10-front table) above.
-- All existing check_ins data is test data, so this is a clean cut rather than
-- keeping two parallel shapes. Deploy this migration and the matching index.html
-- together to minimize the window where the two are out of sync.
alter table check_ins
    drop column if exists status_row,
    drop column if exists status_procurement,
    drop column if exists status_construction,
    drop column if exists status_finance;


-- 3. Admin Quick Win scoring rubric (PMO-only; scores every proposal, not just the winner)
create table if not exists quick_win_evaluations (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    project_name text not null,
    organization text not null,
    proposal_created_at timestamptz not null,
    score_time numeric,
    score_cost numeric,
    score_urgency numeric,
    score_feasibility numeric,
    score_leverage numeric,
    weighted_score numeric,
    decision text,
    evaluated_by text,
    unique (project_name, organization, proposal_created_at)
);

alter table quick_win_evaluations enable row level security;

drop policy if exists "admin full access on quick_win_evaluations" on quick_win_evaluations;
create policy "admin full access on quick_win_evaluations" on quick_win_evaluations
    for all using (is_admin()) with check (is_admin());
