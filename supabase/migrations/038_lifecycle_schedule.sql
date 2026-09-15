-- ============================================================
-- Lifecycle Master Plan — Phase 1 of the phased "ماژول برنامه‌ریزی و
-- زمان‌بندی چرخه عمر پروژه" build-out: the schema for a schedulable
-- tree under each lifecycle phase, plus the dependency links between
-- its nodes. Phase 1 only reads this data (a read-only Gantt embedded
-- in the لایف‌سایکل view); creating/editing rows here, drag-and-drop,
-- the "effective timeline coverage" validation, the bottom-up progress
-- rollup, and baselines are later phases of the same feature and may
-- add more tables/columns on top of this one without reshaping it.
--
--   lifecycle_schedule_items — one row per schedulable node under a
--     phase: a sub-phase (parent_id null) or an activity nested under
--     one (parent_id -> another row here). Arbitrary depth is allowed
--     by the self-reference rather than hard-coding exactly two levels,
--     since the spec's own examples drill down further in places.
--     Progress at a non-leaf node is always COMPUTED bottom-up from its
--     children (same "derived, never typed in" rule as the rest of this
--     module) — manual_actual_pct is only ever meant to be set on a leaf
--     (a node with no children); the frontend enforces that, matching
--     how project_phase_items' polymorphic item_id is validated
--     frontend-side rather than with a DB constraint.
--   lifecycle_schedule_dependencies — FS/SS/FF/SF links between two
--     lifecycle_schedule_items rows, with Lag (positive) / Lead
--     (negative) in days.
--
-- Note: parent_id and predecessor_id/successor_id are not constrained
-- to share the same project_name/phase_code as the row that references
-- them (Postgres has no cross-row check constraint) — the frontend only
-- ever creates them within the same phase, and project_name is kept on
-- both tables too so RLS stays a simple, direct column check rather
-- than a join through the tree.
-- ============================================================

create table lifecycle_schedule_items (
    id bigint generated always as identity primary key,
    project_name text not null,
    phase_code text not null references lifecycle_phases(code),
    parent_id bigint references lifecycle_schedule_items(id) on delete cascade,
    seq int not null default 0,
    title text not null,
    planned_start date,
    planned_finish date,
    weight_pct numeric check (weight_pct is null or weight_pct >= 0),
    manual_actual_pct numeric check (manual_actual_pct is null or manual_actual_pct between 0 and 100),
    updated_at timestamptz not null default now(),
    updated_by text,
    constraint lifecycle_schedule_items_finish_after_start check (
        planned_finish is null or planned_start is null or planned_finish >= planned_start
    )
);
create index lifecycle_schedule_items_project_phase_idx on lifecycle_schedule_items (project_name, phase_code);
create index lifecycle_schedule_items_parent_idx on lifecycle_schedule_items (parent_id);

comment on column lifecycle_schedule_items.weight_pct is 'Weight among siblings under the same parent (or same phase, for a top-level sub-phase) — expected to sum to 100 within that group, validated by the frontend rather than a DB constraint (transiently untrue mid-edit).';
comment on column lifecycle_schedule_items.manual_actual_pct is 'Directly-entered actual % — meaningful only on a leaf node (no children); a parent''s actual % is always computed bottom-up from its children''s weight_pct/manual_actual_pct instead.';

create table lifecycle_schedule_dependencies (
    id bigint generated always as identity primary key,
    project_name text not null,
    predecessor_id bigint not null references lifecycle_schedule_items(id) on delete cascade,
    successor_id bigint not null references lifecycle_schedule_items(id) on delete cascade,
    dep_type text not null default 'FS' check (dep_type in ('FS', 'SS', 'FF', 'SF')),
    lag_days numeric not null default 0,
    updated_at timestamptz not null default now(),
    unique (predecessor_id, successor_id),
    constraint lifecycle_schedule_dependencies_no_self_link check (predecessor_id <> successor_id)
);
create index lifecycle_schedule_dependencies_project_idx on lifecycle_schedule_dependencies (project_name);

comment on column lifecycle_schedule_dependencies.lag_days is 'Positive = Lag (successor waits this many extra days), negative = Lead (successor may start/finish this many days before the dependency point).';

-- ============================================================
-- RLS — identical shape to project_phase_items (migration 033): admin
-- full access; scoped read for anyone with access to the project (or
-- viewing the shared "is_guide" demo project); any manager with access
-- to the project can insert/update/delete their own project's rows.
-- Delete is included here (unlike project_phase_items, which only ever
-- needed upsert) because schedule items/dependencies are genuinely
-- removable — a sub-phase or activity added by mistake, or a
-- dependency that no longer applies.
-- ============================================================
alter table lifecycle_schedule_items enable row level security;
alter table lifecycle_schedule_dependencies enable row level security;

create policy "admin full access on lifecycle_schedule_items" on lifecycle_schedule_items
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_schedule_items" on lifecycle_schedule_items
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_items.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_schedule_items.project_name and projects.is_guide = true)
    );
create policy "manager insert own project on lifecycle_schedule_items" on lifecycle_schedule_items
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_items.project_name
        )
    );
create policy "manager update own project on lifecycle_schedule_items" on lifecycle_schedule_items
    for update using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_items.project_name
        )
    );
create policy "manager delete own project on lifecycle_schedule_items" on lifecycle_schedule_items
    for delete using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_items.project_name
        )
    );

create policy "admin full access on lifecycle_schedule_dependencies" on lifecycle_schedule_dependencies
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_schedule_dependencies" on lifecycle_schedule_dependencies
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_dependencies.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_schedule_dependencies.project_name and projects.is_guide = true)
    );
create policy "manager insert own project on lifecycle_schedule_dependencies" on lifecycle_schedule_dependencies
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_dependencies.project_name
        )
    );
create policy "manager update own project on lifecycle_schedule_dependencies" on lifecycle_schedule_dependencies
    for update using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_dependencies.project_name
        )
    );
create policy "manager delete own project on lifecycle_schedule_dependencies" on lifecycle_schedule_dependencies
    for delete using (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_dependencies.project_name
        )
    );
