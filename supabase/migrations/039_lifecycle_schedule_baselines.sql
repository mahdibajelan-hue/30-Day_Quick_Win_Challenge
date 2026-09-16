-- ============================================================
-- Phase 5 (final phase) of the Lifecycle Master Plan build-out:
-- baseline snapshots. A baseline is a frozen copy of every schedule
-- item's planned dates/weight at the moment it's taken — created once
-- (typically right after the project starts, per the module's own
-- spec), never edited afterward, so it stays a trustworthy fixed
-- reference point to measure schedule drift against over the life of
-- the project. Re-baselining later (e.g. after an approved scope
-- change) is still allowed — it just creates ANOTHER frozen snapshot
-- rather than mutating the first — which is why this is two tables
-- (one baseline header can have many item rows) instead of new
-- columns bolted onto lifecycle_schedule_items itself.
--
--   lifecycle_schedule_baselines      — one row per snapshot taken
--   lifecycle_schedule_baseline_items — that snapshot's frozen copy of
--                                       every schedule item's dates
--
-- schedule_item_id is NOT a foreign key on purpose: the whole point of
-- a frozen historical snapshot is that it must survive the original
-- lifecycle_schedule_items row later being edited or even deleted —
-- title is duplicated here for the same reason, so a baseline stays
-- meaningful even after the live item it once pointed at is gone.
-- ============================================================

create table lifecycle_schedule_baselines (
    id bigint generated always as identity primary key,
    project_name text not null,
    label text not null,
    created_by text not null,
    created_at timestamptz not null default now()
);
create index lifecycle_schedule_baselines_project_idx on lifecycle_schedule_baselines (project_name, created_at);

create table lifecycle_schedule_baseline_items (
    id bigint generated always as identity primary key,
    baseline_id bigint not null references lifecycle_schedule_baselines(id) on delete cascade,
    schedule_item_id bigint not null,
    title text not null,
    planned_start date,
    planned_finish date,
    weight_pct numeric
);
create index lifecycle_schedule_baseline_items_baseline_idx on lifecycle_schedule_baseline_items (baseline_id);
create index lifecycle_schedule_baseline_items_item_idx on lifecycle_schedule_baseline_items (schedule_item_id);

-- ============================================================
-- RLS — same scoping shape as the rest of this module. Deliberately no
-- update policy at all on either table (for anyone, admin included):
-- a baseline that could be edited after the fact wouldn't be a
-- trustworthy fixed reference point any more. Admin can still delete
-- a whole baseline outright (e.g. one created by mistake); nobody can
-- edit one in place.
-- ============================================================
alter table lifecycle_schedule_baselines enable row level security;
alter table lifecycle_schedule_baseline_items enable row level security;

create policy "admin full access on lifecycle_schedule_baselines" on lifecycle_schedule_baselines
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_schedule_baselines" on lifecycle_schedule_baselines
    for select using (
        is_admin() or exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_baselines.project_name
        )
        or exists (select 1 from projects where projects.name = lifecycle_schedule_baselines.project_name and projects.is_guide = true)
    );
create policy "manager insert own project on lifecycle_schedule_baselines" on lifecycle_schedule_baselines
    for insert with check (
        exists (
            select 1 from user_project_access upa
            where upa.user_id = auth.uid() and upa.project_name = lifecycle_schedule_baselines.project_name
        )
    );

create policy "admin full access on lifecycle_schedule_baseline_items" on lifecycle_schedule_baseline_items
    for all using (is_admin()) with check (is_admin());
create policy "scoped read on lifecycle_schedule_baseline_items" on lifecycle_schedule_baseline_items
    for select using (
        is_admin() or exists (
            select 1 from lifecycle_schedule_baselines b
            join user_project_access upa on upa.project_name = b.project_name
            where b.id = lifecycle_schedule_baseline_items.baseline_id and upa.user_id = auth.uid()
        )
        or exists (
            select 1 from lifecycle_schedule_baselines b
            join projects on projects.name = b.project_name and projects.is_guide = true
            where b.id = lifecycle_schedule_baseline_items.baseline_id
        )
    );
create policy "manager insert own project on lifecycle_schedule_baseline_items" on lifecycle_schedule_baseline_items
    for insert with check (
        exists (
            select 1 from lifecycle_schedule_baselines b
            join user_project_access upa on upa.project_name = b.project_name
            where b.id = lifecycle_schedule_baseline_items.baseline_id and upa.user_id = auth.uid()
        )
    );
