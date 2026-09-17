-- ============================================================
-- Master Project Lifecycle & Schedule — Execution Strategy engine.
--
-- Adds an ADDITIVE scheduling layer on top of the existing, unchanged
-- G1..G9 lifecycle (lifecycle_phases, project_lifecycle_phases from
-- migration 033): it only ever computes and writes
-- planned_start/planned_finish onto the existing
-- project_lifecycle_phases rows, so the Master Plan Gantt
-- (lcMasterPlanHtml/lcGanttGridHtml, migrations 038/039) needs no
-- structural change to read it, and the 9-gate structure, each gate's
-- objectives/outputs/criteria and pass thresholds are completely
-- untouched by this migration.
--
-- Per the spec's own "never fake speed" rule, per-phase Duration is
-- ONE org-wide table shared by every Execution Strategy — a strategy
-- only ever changes the DEPENDENCY graph between phases (how much
-- they overlap), never how long a phase itself takes.
--
--   lifecycle_phase_durations             — normal/baseline duration
--                                            per phase (org-wide,
--                                            admin-edit, one source of
--                                            truth for every strategy)
--   lifecycle_strategy_phase_dependencies — per Execution Strategy,
--                                            which phase-to-phase
--                                            overlap (FS/SS/FF/SF +
--                                            Lag) applies; Sequential
--                                            has none on purpose (a
--                                            pure Finish-to-Start
--                                            chain)
--   lifecycle_master_schedule             — one row per project: the
--                                            chosen strategy, project
--                                            start date and its
--                                            governance status
--                                            (Draft → ... → Completed)
--   lifecycle_master_schedule_versions    — immutable snapshot taken
--                                            on every baseline/
--                                            approved revision (V1.0,
--                                            V1.1, V2.0…), so Baseline
--                                            vs Current stays
--                                            answerable later
--
-- The forward/backward-pass CPM math over these tables lives in the
-- app (lcComputeMasterSchedule / lcComputeMasterCriticalPath),
-- mirroring the same FS/SS/FF/SF + Lag/Lead semantics already proven
-- for lifecycle_schedule_dependencies (migration 038).
-- ============================================================

create table lifecycle_phase_durations (
    phase_code text primary key references lifecycle_phases(code),
    duration_days int not null check (duration_days > 0),
    updated_at timestamptz not null default now(),
    updated_by text
);
comment on table lifecycle_phase_durations is 'Normal/Sequential duration of each of the 9 official phases, in days — the single source of truth every Execution Strategy schedules against. Editable master data: a strategy must never shorten this to fake a faster schedule, only overlap the phases differently via lifecycle_strategy_phase_dependencies.';

-- Verified (via a standalone CPM simulation) to reproduce the
-- Sequential targets exactly: Start-up at cumulative month 41 (G7
-- finish), Final Completion at month 46 (G9 finish), 30 days/month.
insert into lifecycle_phase_durations (phase_code, duration_days) values
    ('G1', 60),
    ('G2', 30),
    ('G3', 120),
    ('G4', 180),
    ('G5', 180),
    ('G6', 600),
    ('G7', 60),
    ('G8', 120),
    ('G9', 30);

create table lifecycle_strategy_phase_dependencies (
    id bigint generated always as identity primary key,
    strategy text not null check (strategy in ('sequential', 'overlapping', 'fast_track', 'emergency_fast_track')),
    pred_phase_code text not null references lifecycle_phases(code),
    succ_phase_code text not null references lifecycle_phases(code),
    dep_type text not null check (dep_type in ('FS', 'SS', 'FF', 'SF')),
    lag_days int not null default 0,
    unique (strategy, succ_phase_code)
);
comment on table lifecycle_strategy_phase_dependencies is 'Per Execution Strategy phase-to-phase overlap. A phase with no row here for its strategy defaults to a plain Finish-to-Start from the immediately preceding phase (in lifecycle_phases.sort_order) — which is why Sequential has no rows at all.';

-- Overlapping: verified start-up ≈36 months, final ≈41 months
-- (target 35-38 / 40-43 per the module spec).
insert into lifecycle_strategy_phase_dependencies (strategy, pred_phase_code, succ_phase_code, dep_type, lag_days) values
    ('overlapping', 'G4', 'G5', 'SS', 90),
    ('overlapping', 'G6', 'G7', 'SS', 540);

-- Fast-Track: verified start-up ≈31 months, final ≈35 months
-- (target 29-32 / 32-35).
insert into lifecycle_strategy_phase_dependencies (strategy, pred_phase_code, succ_phase_code, dep_type, lag_days) values
    ('fast_track', 'G2', 'G3', 'SS', 0),
    ('fast_track', 'G3', 'G4', 'SS', 60),
    ('fast_track', 'G4', 'G5', 'SS', 60),
    ('fast_track', 'G6', 'G7', 'SS', 510),
    ('fast_track', 'G7', 'G8', 'SS', 30);

-- Emergency Fast-Track: verified start-up ≈25 months, final ≈28.5
-- months (target 24-30 / 27-32).
insert into lifecycle_strategy_phase_dependencies (strategy, pred_phase_code, succ_phase_code, dep_type, lag_days) values
    ('emergency_fast_track', 'G1', 'G2', 'SS', 30),
    ('emergency_fast_track', 'G2', 'G3', 'SS', 0),
    ('emergency_fast_track', 'G3', 'G4', 'SS', 30),
    ('emergency_fast_track', 'G4', 'G5', 'SS', 60),
    ('emergency_fast_track', 'G5', 'G6', 'SS', 90),
    ('emergency_fast_track', 'G6', 'G7', 'SS', 480),
    ('emergency_fast_track', 'G7', 'G8', 'SS', 15);

create table lifecycle_master_schedule (
    id bigint generated always as identity primary key,
    project_name text not null unique,
    execution_strategy text not null default 'sequential'
        check (execution_strategy in ('sequential', 'overlapping', 'fast_track', 'emergency_fast_track')),
    project_start_date date,
    governance_status text not null default 'draft'
        check (governance_status in ('draft', 'proposed', 'reviewed', 'approved', 'baseline', 'in_execution', 'revised', 'completed')),
    active_baseline_version_id bigint,
    updated_at timestamptz not null default now(),
    updated_by text
);

create table lifecycle_master_schedule_versions (
    id bigint generated always as identity primary key,
    project_name text not null,
    version_label text not null,
    is_baseline boolean not null default false,
    execution_strategy text not null,
    project_start_date date not null,
    startup_date date,
    completion_date date,
    total_duration_days int,
    change_reason text,
    created_by text not null,
    created_at timestamptz not null default now(),
    unique (project_name, version_label)
);
create index lifecycle_master_schedule_versions_project_idx on lifecycle_master_schedule_versions (project_name, created_at);

alter table lifecycle_master_schedule
    add constraint lifecycle_master_schedule_baseline_fk
    foreign key (active_baseline_version_id) references lifecycle_master_schedule_versions(id);

comment on table lifecycle_master_schedule_versions is 'One immutable row per baseline or approved revision (V1.0, V1.1, V2.0…) — never updated after insert, same reasoning as lifecycle_schedule_baselines (migration 039): a frozen reference point that could be edited afterward would not be trustworthy.';

-- ============================================================
-- RLS — same scoping shape as the rest of this module.
-- ============================================================
alter table lifecycle_phase_durations enable row level security;
alter table lifecycle_strategy_phase_dependencies enable row level security;
alter table lifecycle_master_schedule enable row level security;
alter table lifecycle_master_schedule_versions enable row level security;

create policy "authenticated read lifecycle_phase_durations" on lifecycle_phase_durations
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_phase_durations" on lifecycle_phase_durations
    for all using (is_admin()) with check (is_admin());

create policy "authenticated read lifecycle_strategy_phase_dependencies" on lifecycle_strategy_phase_dependencies
    for select using (auth.uid() is not null);
create policy "admin write lifecycle_strategy_phase_dependencies" on lifecycle_strategy_phase_dependencies
    for all using (is_admin()) with check (is_admin());

create policy "admin full access on lifecycle_master_schedule" on lifecycle_master_schedule
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_master_schedule" on lifecycle_master_schedule
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_master_schedule.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_master_schedule.project_name and projects.is_guide = true)
    );
create policy "manager write own project on lifecycle_master_schedule" on lifecycle_master_schedule
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_master_schedule.project_name
        )
    );
create policy "manager update own project on lifecycle_master_schedule" on lifecycle_master_schedule
    for update using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_master_schedule.project_name
        )
    );

create policy "admin full access on lifecycle_master_schedule_versions" on lifecycle_master_schedule_versions
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_master_schedule_versions" on lifecycle_master_schedule_versions
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_master_schedule_versions.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_master_schedule_versions.project_name and projects.is_guide = true)
    );
create policy "manager insert own project on lifecycle_master_schedule_versions" on lifecycle_master_schedule_versions
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_master_schedule_versions.project_name
        )
    );
